#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  dump_tree.sh — Dump de projeto + árvore de diretórios                      ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  USO                                                                         ║
# ║    ./dump_tree.sh -g [OPÇÕES]    Gera o dump                                 ║
# ║    ./dump_tree.sh -v [-t]        Verifica integridade do dump                ║
# ║    ./dump_tree.sh -h             Exibe esta ajuda                            ║
# ║                                                                              ║
# ║  OPÇÕES DO MODO -g                                                           ║
# ║    -n              Dry-run: lista arquivos sem gerar dump                    ║
# ║    -t              Timestamp no nome do arquivo de saída                     ║
# ║                      ex: dump_20260218_1401.md                               ║
# ║    -d              Exclui docs/, *.md, LICENSE e CHANGELOG                  ║
# ║    -o <subpasta>   Inclui apenas a subpasta especificada                     ║
# ║                      ex: ./dump_tree.sh -g -o src/validation                 ║
# ║    -e <pasta>      Exclui pasta extra (repetível)                            ║
# ║                      ex: ./dump_tree.sh -g -e vendor -e third_party          ║
# ║    -f              Força geração mesmo sem sinais de projeto (--force)       ║
# ║    -y              Responde sim a todas as confirmações (--yes)              ║
# ║    -q              Silencioso: sem cores, sem interação (--quiet)            ║
# ║    --max-tokens N  Aborta se estimativa de tokens ultrapassar N              ║
# ║                      ex: ./dump_tree.sh -g --max-tokens 100000               ║
# ║                                                                              ║
# ║  VARIÁVEIS DE AMBIENTE                                                       ║
# ║    COMENTARIO="texto"   Adiciona contexto de retomada no cabeçalho do dump  ║
# ║                      ex: COMENTARIO="bug no parser" ./dump_tree.sh -g -t    ║
# ║                                                                              ║
# ║  EXEMPLOS                                                                    ║
# ║    ./dump_tree.sh -g                          # dump completo                ║
# ║    ./dump_tree.sh -g -n                       # auditar sem gerar            ║
# ║    ./dump_tree.sh -g -t                       # dump com timestamp           ║
# ║    ./dump_tree.sh -g -d -o src                # só src/, sem docs            ║
# ║    ./dump_tree.sh -g -e vendor -e libs        # exclui pastas extras         ║
# ║    ./dump_tree.sh -g --max-tokens 80000       # limita tamanho               ║
# ║    ./dump_tree.sh -g -t -d -o src/xml         # combinado com timestamp      ║
# ║    ./dump_tree.sh -g -f                       # força mesmo sem projeto      ║
# ║    ./dump_tree.sh -g -y                       # sem confirmações interativas ║
# ║    ./dump_tree.sh -g -q                       # modo silencioso/CI           ║
# ║    ./dump_tree.sh -v                          # verificar dump.md            ║
# ║    ./dump_tree.sh -v -t                       # verificar dump com timestamp ║
# ║    COMENTARIO="travado no parse" ./dump_tree.sh -g -t                       ║
# ║                                                                              ║
# ║  ARQUIVOS GERADOS                                                            ║
# ║    dump.md          Conteúdo completo do projeto em Markdown                 ║
# ║    dump.md.sha256   Checksum SHA-256 para verificação de integridade         ║
# ║    dump.log         Log detalhado da execução                                ║
# ║                                                                              ║
# ║  DEPENDÊNCIAS (instaladas automaticamente se ausentes)                       ║
# ║    tree  find  file  stat  sha256sum  tput                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Cores (fallback seguro se terminal não suportar) ─────────────────────────
if tput colors &>/dev/null && (( $(tput colors) >= 8 )); then
    C_GREEN="\033[0;32m"
    C_YELLOW="\033[0;33m"
    C_RED="\033[0;31m"
    C_CYAN="\033[0;36m"
    C_BOLD="\033[1m"
    C_RESET="\033[0m"
else
    C_GREEN="" C_YELLOW="" C_RED="" C_CYAN="" C_BOLD="" C_RESET=""
fi

info()   { echo -e "${C_GREEN}  ✓${C_RESET} $*"; }
warn()   { echo -e "${C_YELLOW}  ⚠${C_RESET} $*"; }
erro()   { echo -e "${C_RED}  ✗${C_RESET} $*" >&2; }
titulo() { echo -e "${C_BOLD}${C_CYAN}$*${C_RESET}"; }

# ══════════════════════════════════════════════════════════════════════════════
# DETECÇÃO DE DISTRO E INSTALAÇÃO DE DEPENDÊNCIAS
# ══════════════════════════════════════════════════════════════════════════════

declare -A PKG_MAP=(
    [tree]="fedora:tree debian:tree arch:tree opensuse:tree"
    [file]="fedora:file debian:file arch:file opensuse:file"
    [sha256sum]="fedora:coreutils debian:coreutils arch:coreutils opensuse:coreutils"
    [tput]="fedora:ncurses debian:ncurses-bin arch:ncurses opensuse:ncurses-utils"
)

detect_distro() {
    local id="" id_like=""

    if [[ -f /etc/os-release ]]; then
        id="$(     grep -E '^ID='      /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
        id_like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
    fi

    case "$id" in
        fedora)                       echo "fedora";   return ;;
        rhel|centos|almalinux|rocky)  echo "rhel";     return ;;
        debian)                       echo "debian";   return ;;
        ubuntu|linuxmint|pop)         echo "ubuntu";   return ;;
        arch|manjaro|endeavouros)     echo "arch";     return ;;
        opensuse*|sles)               echo "opensuse"; return ;;
    esac

    for token in $id_like; do
        case "$token" in
            fedora|rhel)   echo "fedora";   return ;;
            debian|ubuntu) echo "ubuntu";   return ;;
            arch)          echo "arch";     return ;;
            suse)          echo "opensuse"; return ;;
        esac
    done

    echo "unknown"
}

get_pkg_name() {
    local binary="$1"
    local distro="$2"
    local entry="${PKG_MAP[$binary]:-}"
    [[ -z "$entry" ]] && echo "$binary" && return

    for pair in $entry; do
        local key="${pair%%:*}"
        local pkg="${pair##*:}"
        if [[ "$distro" == "$key"* || "$key" == "$distro"* ]]; then
            echo "$pkg"
            return
        fi
    done
    echo "$binary"
}

install_pkg() {
    local pkg="$1"
    local distro="$2"
    echo -e "  ${C_YELLOW}→ Instalando '${pkg}'...${C_RESET}"
    case "$distro" in
        fedora|rhel)   sudo dnf install -y "$pkg" ;;
        ubuntu|debian) sudo apt-get install -y "$pkg" ;;
        arch)          sudo pacman -S --noconfirm "$pkg" ;;
        opensuse)      sudo zypper install -y "$pkg" ;;
        *)
            erro "Distro não reconhecida. Instale '$pkg' manualmente e tente novamente."
            exit 1
            ;;
    esac
}

# ─── Configuração (declarada antes do parse para check_deps poder ler QUIET) ──
SCRIPT_NAME="$(basename "$0")"
ROOT_DIR="$(pwd)"
MAX_SIZE_KB=50
MAX_TOKENS=0
MODE=""
DRY_RUN=0
USE_TIMESTAMP=0
NO_DOCS=0
ONLY_SUBDIR=""
FORCE=0
YES_ALL=0
QUIET=0
COMENTARIO="${COMENTARIO:-}"

EXCLUDE_DIRS=( "build" ".git" ".cache" "Testing" )
TREE_EXCLUDE="build|.git|.cache|Testing"

# Variáveis de controle de limpeza (usadas no trap)
DUMP_FILE=""
CHECKSUM_FILE=""
LOG_FILE=""
DUMP_COMPLETO=0

# ══════════════════════════════════════════════════════════════════════════════
# TRAP — limpeza em caso de interrupção ou erro inesperado
# ══════════════════════════════════════════════════════════════════════════════
cleanup() {
    local exit_code=$?
    # Só age se estava no meio de uma geração e o dump não foi concluído
    if [[ -n "$DUMP_FILE" && -f "$DUMP_FILE" && "$DUMP_COMPLETO" -eq 0 ]]; then
        (( ! QUIET )) && echo ""
        erro "Execução interrompida antes da conclusão."
        erro "Dump parcial removido: ${DUMP_FILE}"
        rm -f "${DUMP_FILE}" "${CHECKSUM_FILE:-}" "${LOG_FILE:-}"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ─── Suporte a opções longas ──────────────────────────────────────────────────
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)         ARGS+=( "-h" ) ;;
        --force)        ARGS+=( "-f" ) ;;
        --yes)          ARGS+=( "-y" ) ;;
        --quiet)        ARGS+=( "-q" ) ;;
        --max-tokens)   shift; ARGS+=( "-m" "$1" ) ;;
        --max-tokens=*) ARGS+=( "-m" "${1#*=}" ) ;;
        *)              ARGS+=( "$1" ) ;;
    esac
    shift
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# ─── Sem argumentos ───────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    echo ""
    titulo "  dump_tree.sh — Dump de projeto + árvore de diretórios"
    echo ""
    echo "  MODOS DISPONÍVEIS:"
    echo "    -g            Gera o dump completo do projeto"
    echo "    -g -n         Dry-run: audita arquivos sem gerar dump"
    echo "    -v            Verifica integridade do dump gerado"
    echo "    -h / --help   Exibe a ajuda completa com todos os exemplos"
    echo ""
    echo "  EXEMPLOS RÁPIDOS:"
    echo "    ./dump_tree.sh -g                # gerar dump completo"
    echo "    ./dump_tree.sh -g -n             # auditar sem gerar"
    echo "    ./dump_tree.sh -g -t             # gerar com timestamp"
    echo "    ./dump_tree.sh -g -f             # forçar mesmo sem sinais de projeto"
    echo "    ./dump_tree.sh -g -y             # sem confirmações interativas"
    echo "    ./dump_tree.sh -g -q             # modo silencioso (CI/scripts)"
    echo "    ./dump_tree.sh -g -d -o src      # só src/, sem docs"
    echo "    ./dump_tree.sh -v                # verificar integridade"
    echo ""
    echo -e "  ${C_CYAN}Para instruções detalhadas: ./dump_tree.sh --help${C_RESET}"
    echo ""
    exit 0
fi

# ─── Parse de argumentos ──────────────────────────────────────────────────────
while getopts ":gvhntfyqo:de:m:" opt; do
    case $opt in
        g) MODE="gerar" ;;
        v) MODE="verificar" ;;
        h) MODE="help" ;;
        n) DRY_RUN=1 ;;
        t) USE_TIMESTAMP=1 ;;
        d) NO_DOCS=1 ;;
        f) FORCE=1 ;;
        y) YES_ALL=1 ;;
        q) QUIET=1; YES_ALL=1 ;;
        o) ONLY_SUBDIR="$OPTARG" ;;
        e)
            EXCLUDE_DIRS+=( "$OPTARG" )
            TREE_EXCLUDE="${TREE_EXCLUDE}|${OPTARG}"
            ;;
        m) MAX_TOKENS="$OPTARG" ;;
        :)
            erro "Opção -${OPTARG} requer um argumento."
            erro "Para instruções: ./dump_tree.sh --help"
            exit 1
            ;;
        *)
            erro "Opção desconhecida: -${OPTARG}"
            erro "Para instruções: ./dump_tree.sh --help"
            exit 1
            ;;
    esac
done

# ─── Modo help (antes de checar dependências) ─────────────────────────────────
if [[ "$MODE" == "help" ]]; then
    grep "^# ║" "$0" | sed 's/^# //'
    exit 0
fi

# ─── Valida --max-tokens como inteiro positivo ────────────────────────────────
if [[ -n "$MAX_TOKENS" && "$MAX_TOKENS" != "0" ]]; then
    if ! [[ "$MAX_TOKENS" =~ ^[0-9]+$ ]] || (( MAX_TOKENS == 0 )); then
        erro "--max-tokens requer um número inteiro positivo. Recebido: '${MAX_TOKENS}'"
        exit 1
    fi
fi

# ─── Valida -o contra path traversal ─────────────────────────────────────────
if [[ -n "$ONLY_SUBDIR" ]]; then
    # Resolve o caminho real e verifica se está dentro de ROOT_DIR
    RESOLVED_SUBDIR="$(realpath "${ROOT_DIR}/${ONLY_SUBDIR}" 2>/dev/null || true)"
    if [[ -z "$RESOLVED_SUBDIR" || "$RESOLVED_SUBDIR" != "${ROOT_DIR}"/* ]]; then
        erro "Subpasta '${ONLY_SUBDIR}' está fora do diretório raiz do projeto."
        erro "Use um caminho relativo dentro de: ${ROOT_DIR}"
        exit 1
    fi
    if [[ ! -d "$RESOLVED_SUBDIR" ]]; then
        erro "Subpasta '${ONLY_SUBDIR}' não encontrada em ${ROOT_DIR}."
        exit 1
    fi
fi

# ─── Verifica e instala dependências (após help para não bloquear -h) ─────────
check_and_install_deps() {
    local distro
    distro="$(detect_distro)"
    local deps=( tree file sha256sum tput find stat )
    local missing=()

    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=( "$dep" )
    done

    (( ${#missing[@]} == 0 )) && return 0

    if (( QUIET )); then
        erro "Dependências ausentes: ${missing[*]}. Instale manualmente e tente novamente."
        exit 1
    fi

    echo ""
    titulo "  Verificando dependências..."
    echo -e "  Distro detectada : ${C_BOLD}${distro}${C_RESET}"
    warn "Dependências ausentes: ${missing[*]}"
    echo ""

    local resposta="s"
    if (( ! YES_ALL )); then
        read -r -p "  Deseja instalar as dependências ausentes agora? [s/N] " resposta
        echo ""
    fi

    if [[ "${resposta,,}" != "s" ]]; then
        erro "Dependências não instaladas. O script não pode continuar."
        exit 1
    fi

    for dep in "${missing[@]}"; do
        local pkg
        pkg="$(get_pkg_name "$dep" "$distro")"
        install_pkg "$pkg" "$distro"
        if command -v "$dep" &>/dev/null; then
            info "'${dep}' instalado com sucesso."
        else
            erro "Falha ao instalar '${dep}'. Instale manualmente e tente novamente."
            exit 1
        fi
    done

    echo ""
    info "Todas as dependências instaladas."
    echo ""
}

check_and_install_deps

if [[ -z "$MODE" ]]; then
    erro "Nenhum modo especificado. Use -g para gerar ou -v para verificar."
    erro "Para instruções: ./dump_tree.sh --help"
    exit 1
fi

# ─── Nomes dos arquivos ────────────────────────────────────────────────────────
if (( USE_TIMESTAMP )); then
    TS="$(date '+%Y%m%d_%H%M')"
    DUMP_FILE="dump_${TS}.md"
    LOG_FILE="dump_${TS}.log"
else
    DUMP_FILE="dump.md"
    LOG_FILE="dump.log"
fi
CHECKSUM_FILE="${DUMP_FILE}.sha256"

# ══════════════════════════════════════════════════════════════════════════════
# MODO VERIFICAR (-v)
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "verificar" ]]; then
    # Desativa o trap de limpeza — não há arquivo sendo gerado aqui
    trap - EXIT INT TERM

    # Se não existe dump.md e -t não foi passado, tenta o dump com timestamp mais recente
    if [[ ! -f "${DUMP_FILE}" ]] && (( ! USE_TIMESTAMP )); then
        LATEST="$(ls -t dump_*.md 2>/dev/null | head -1 || true)"
        if [[ -n "$LATEST" ]]; then
            DUMP_FILE="$LATEST"
            CHECKSUM_FILE="${DUMP_FILE}.sha256"
            warn "dump.md não encontrado. Usando o mais recente: ${DUMP_FILE}"
        fi
    fi

    titulo "╔══════════════════════════════════════════════════════════════╗"
    titulo "║  VERIFICAÇÃO DE INTEGRIDADE SHA-256                          ║"
    titulo "╚══════════════════════════════════════════════════════════════╝"
    echo "  Dump     : ${DUMP_FILE}"
    echo "  Checksum : ${CHECKSUM_FILE}"
    echo ""

    if [[ ! -f "${DUMP_FILE}" ]]; then
        erro "Arquivo '${DUMP_FILE}' não encontrado."
        erro "Gere o dump primeiro com: ./dump_tree.sh -g"
        exit 1
    fi

    if [[ ! -f "${CHECKSUM_FILE}" ]]; then
        erro "Arquivo de checksum '${CHECKSUM_FILE}' não encontrado."
        erro "O dump pode ter sido gerado sem checksum ou foi removido."
        erro "Gere o dump novamente com: ./dump_tree.sh -g"
        exit 1
    fi

    if [[ ! -r "${DUMP_FILE}" ]]; then
        erro "Sem permissão de leitura em '${DUMP_FILE}'."
        exit 1
    fi

    echo "  Calculando SHA-256..."
    if sha256sum -c "${CHECKSUM_FILE}" 2>/dev/null; then
        echo ""
        info "Integridade confirmada — o dump não foi modificado após a geração."
    else
        echo ""
        erro "FALHA NA VERIFICAÇÃO — o dump foi modificado após a geração."
        erro "Não utilize este arquivo. Gere um novo dump com: ./dump_tree.sh -g"
        exit 2
    fi
    exit 0
fi

# ─── Função auxiliar de confirmação ───────────────────────────────────────────
confirmar() {
    local msg="$1"
    if (( FORCE || YES_ALL )); then
        (( ! QUIET )) && warn "${msg} Prosseguindo por -f/-y."
        return 0
    fi
    warn "$msg"
    local resposta
    read -r -p "  Deseja continuar? [s/N] " resposta
    [[ "${resposta,,}" == "s" ]]
}

# ─── Detecta se é projeto ─────────────────────────────────────────────────────
if [[ "$MODE" == "gerar" ]] && (( ! FORCE )); then
    high_signals=0 medium_signals=0 low_signals=0

    # Usa subshell para evitar que o 'set -e' mate o script quando ls não encontra arquivos
    if [[ -d ".git" ]] || \
       ( ls CMakeLists.txt Makefile meson.build build.gradle pom.xml \
             package.json Cargo.toml pyproject.toml setup.py \
             composer.json go.mod 2>/dev/null | grep -q . ) ; then
        high_signals=1
    fi

    if find . -maxdepth 3 -type f \( \
            -name "*.c"    -o -name "*.cpp"  -o -name "*.py"  -o \
            -name "*.js"   -o -name "*.ts"   -o -name "*.rs"  -o \
            -name "*.go"   -o -name "*.java" -o -name "*.sh"  -o \
            -name "*.rb"   -o -name "*.php"  -o -name "*.kt"  -o \
            -name "*.cs"   -o -name "*.lua" \
        \) -print -quit 2>/dev/null | grep -q . ; then
        medium_signals=1
    fi

    if ls README.md LICENSE 2>/dev/null | grep -q . ; then
        low_signals=1
    fi

    if (( high_signals >= 1 )); then
        : # projeto confirmado, prossegue silenciosamente
    elif (( medium_signals || low_signals )); then
        confirmar "Esta pasta parece ser um projeto parcial (sinais médios ou baixos detectados)." || \
            { erro "Operação cancelada."; exit 1; }
    else
        confirmar "Esta pasta não parece ser um projeto (nenhum sinal detectado)." || \
            { erro "Operação cancelada."; exit 1; }
    fi
fi

# ─── Verifica permissão de escrita no diretório atual ─────────────────────────
if [[ ! -w "${ROOT_DIR}" ]]; then
    erro "Sem permissão de escrita em '${ROOT_DIR}'."
    erro "Verifique as permissões do diretório e tente novamente."
    exit 1
fi

# ─── Verifica espaço em disco disponível ──────────────────────────────────────
verificar_espaco() {
    local disponivel_kb
    disponivel_kb=$(df -k "${ROOT_DIR}" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -z "$disponivel_kb" ]]; then
        warn "Não foi possível verificar o espaço em disco disponível."
        return
    fi
    # Estimativa conservadora: total de arquivos + 20% de overhead do Markdown
    local total_kb
    total_kb=$(du -sk "${SEARCH_ROOT:-${ROOT_DIR}}" 2>/dev/null | awk '{print $1}')
    if [[ -z "$total_kb" ]]; then return; fi
    local necessario_kb=$(( total_kb + total_kb / 5 ))
    if (( necessario_kb > disponivel_kb )); then
        erro "Espaço em disco insuficiente."
        erro "  Necessário (estimado) : ${necessario_kb}KB"
        erro "  Disponível            : ${disponivel_kb}KB"
        erro "Libere espaço e tente novamente, ou use -o/-d/-e para reduzir o escopo."
        exit 1
    fi
}

# ─── Detecta linguagem (retorna identificador de bloco de código Markdown) ────
detect_language() {
    case "${1,,}" in
        *.cpp|*.cc|*.cxx)         echo "cpp" ;;
        *.c)                      echo "c" ;;
        *.h|*.hpp|*.hxx)          echo "c" ;;
        *.cmake|cmakelists.txt)   echo "cmake" ;;
        *.sh|*.bash)              echo "bash" ;;
        *.py)                     echo "python" ;;
        *.md)                     echo "markdown" ;;
        *.xml)                    echo "xml" ;;
        *.json)                   echo "json" ;;
        *.yaml|*.yml)             echo "yaml" ;;
        *.toml)                   echo "toml" ;;
        *.rs)                     echo "rust" ;;
        *.go)                     echo "go" ;;
        *.java)                   echo "java" ;;
        *.js)                     echo "javascript" ;;
        *.ts)                     echo "typescript" ;;
        *.rb)                     echo "ruby" ;;
        *.php)                    echo "php" ;;
        *.cs)                     echo "csharp" ;;
        *.kt|*.kts)               echo "kotlin" ;;
        *.lua)                    echo "lua" ;;
        *.r|*.rmd)                echo "r" ;;
        *.sql)                    echo "sql" ;;
        *.tf|*.tfvars)            echo "hcl" ;;
        *.ini|*.cfg|*.conf)       echo "ini" ;;
        *.env|.env*)              echo "bash" ;;
        dockerfile|*.dockerfile)  echo "dockerfile" ;;
        *.txt|*.log)              echo "text" ;;
        *)                        echo "text" ;;
    esac
}

# ─── Monta exclusões para o find ──────────────────────────────────────────────
build_find_excludes() {
    local -n _arr=$1
    _arr=()
    local search_root="${ROOT_DIR}"
    [[ -n "$ONLY_SUBDIR" ]] && search_root="${ROOT_DIR}/${ONLY_SUBDIR}"

    for dir in "${EXCLUDE_DIRS[@]}"; do
        _arr+=( -path "${search_root}/${dir}" -prune -o )
    done
    _arr+=( -path "${ROOT_DIR}/${DUMP_FILE}"     -prune -o )
    _arr+=( -path "${ROOT_DIR}/${CHECKSUM_FILE}" -prune -o )
    _arr+=( -path "${ROOT_DIR}/${LOG_FILE}"      -prune -o )
    _arr+=( -path "${ROOT_DIR}/${SCRIPT_NAME}"   -prune -o )

    if (( NO_DOCS )); then
        _arr+=( -path "${search_root}/docs" -prune -o )
        _arr+=( -name "*.md"       -prune -o )
        _arr+=( -name "LICENSE"    -prune -o )
        _arr+=( -name "CHANGELOG*" -prune -o )
    fi
}

# ─── Coleta arquivos ──────────────────────────────────────────────────────────
declare -a FIND_EXCLUDES=()
build_find_excludes FIND_EXCLUDES

SEARCH_ROOT="${ROOT_DIR}"
[[ -n "$ONLY_SUBDIR" ]] && SEARCH_ROOT="${RESOLVED_SUBDIR}"

mapfile -t FILES < <(
    find "${SEARCH_ROOT}" \
        "${FIND_EXCLUDES[@]}" \
        -type f -size +0c -print \
    | sort
)

TOTAL=${#FILES[@]}

# ─── Aviso de dump vazio ──────────────────────────────────────────────────────
if (( TOTAL == 0 )); then
    erro "Nenhum arquivo encontrado para incluir no dump."
    if [[ -n "$ONLY_SUBDIR" ]]; then
        erro "O escopo '${ONLY_SUBDIR}/' está vazio ou todos os arquivos foram excluídos."
    else
        erro "Verifique as opções -d, -e e --max-tokens para ver se o escopo está muito restrito."
    fi
    exit 1
fi

LOG_ENTRIES=()
log() { LOG_ENTRIES+=( "$(date '+%H:%M:%S') $*" ); }
log "Arquivos encontrados: ${TOTAL}"

flush_log() {
    : > "${LOG_FILE}"
    {
        echo "============================================================"
        echo "  LOG DE EXECUÇÃO — dump_tree.sh"
        echo "  Projeto  : ${ROOT_DIR}"
        echo "  Data     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "  Distro   : $(detect_distro)"
        echo "  Dump     : ${DUMP_FILE}"
        [[ -n "$ONLY_SUBDIR" ]] && echo "  Escopo   : ${ONLY_SUBDIR}/"
        (( NO_DOCS ))           && echo "  Modo     : -d ativo"
        (( MAX_TOKENS > 0 ))    && echo "  Limite   : ${MAX_TOKENS} tokens"
        (( FORCE ))             && echo "  Flags    : -f (force)"
        (( YES_ALL ))           && echo "  Flags    : -y (yes-all)"
        (( QUIET ))             && echo "  Flags    : -q (quiet)"
        echo "============================================================"
        echo ""
        for entry in "${LOG_ENTRIES[@]}"; do echo "  ${entry}"; done
        echo ""
        echo "============================================================"
        echo "  FIM DO LOG"
        echo "============================================================"
    } >> "${LOG_FILE}"
}

# ─── Estimativa prévia (--max-tokens) ─────────────────────────────────────────
if (( MAX_TOKENS > 0 )); then
    EST_BYTES_PRE=0
    for fp in "${FILES[@]}"; do
        # Arquivo pode ter sumido entre find e stat (race condition) — trata com segurança
        if [[ -f "$fp" ]]; then
            EST_BYTES_PRE=$(( EST_BYTES_PRE + $(stat -c%s "${fp}") ))
        fi
    done
    # Fator 3.5 para melhor precisão com texto em PT-BR (UTF-8 multibyte)
    EST_TOKENS_PRE=$(( EST_BYTES_PRE * 2 / 7 ))
    log "Estimativa de tokens (pré-geração): ~${EST_TOKENS_PRE}"

    if (( EST_TOKENS_PRE > MAX_TOKENS )); then
        erro "Estimativa de tokens (~${EST_TOKENS_PRE}) ultrapassa o limite (${MAX_TOKENS})."
        erro "Reduza o escopo com -o <subpasta>, -d ou -e <pasta> e tente novamente."
        exit 3
    fi
fi

# ─── Função unificada de processamento de arquivo ────────────────────────────
# Retorna via stdout: "bin", "large" ou "ok"
# Em modo "dump", escreve o conteúdo Markdown no arquivo destino
processar_arquivo() {
    local filepath="$1"
    local modo="$2"       # "dry" ou "dump"
    local dump_dest="${3:-}"

    # Race condition: arquivo pode ter sido removido após o find
    if [[ ! -f "$filepath" ]]; then
        if [[ "$modo" == "dump" ]]; then
            local rel_missing="${filepath#"${ROOT_DIR}/"}"
            {
                echo ""
                echo "---"
                echo ""
                echo "### \`${rel_missing}\`  — ARQUIVO REMOVIDO DURANTE A EXECUÇÃO"
                echo ""
            } >> "${dump_dest}"
            log "AVISO: arquivo removido durante execução: ${rel_missing}"
        fi
        echo "ok"
        return
    fi

    local rel_path="${filepath#"${ROOT_DIR}/"}"
    local lang
    lang=$(detect_language "$(basename "${filepath}")")

    local raw_bytes
    raw_bytes=$(stat -c%s "${filepath}" 2>/dev/null || echo "0")
    local size_kb=$(( (raw_bytes + 1023) / 1024 ))

    # Binário?
    if ! file --mime-type "${filepath}" 2>/dev/null | grep -qE 'text/|xml|json|x-empty'; then
        if [[ "$modo" == "dry" ]]; then
            echo -e "${C_YELLOW}  [BINÁRIO  ]${C_RESET} ${rel_path}"
        else
            {
                echo ""
                echo "---"
                echo ""
                echo "### \`${rel_path}\`  — BINÁRIO IGNORADO"
                echo ""
            } >> "${dump_dest}"
            log "BINÁRIO ignorado: ${rel_path}"
        fi
        echo "bin"
        return
    fi

    # Arquivo grande?
    local size_warn=""
    if (( size_kb > MAX_SIZE_KB )); then
        size_warn="⚠ ${size_kb}KB"
        if [[ "$modo" == "dry" ]]; then
            printf "${C_YELLOW}  [⚠ %4dKB]${C_RESET} %-52s [%s]\n" \
                "${size_kb}" "${rel_path}" "${lang}"
        fi
        log "ARQUIVO GRANDE (${size_kb}KB): ${rel_path}"
        echo "large"
    else
        if [[ "$modo" == "dry" ]]; then
            printf "  [  %4dKB] %-52s [%s]\n" "${size_kb}" "${rel_path}" "${lang}"
        fi
        echo "ok"
    fi

    # Grava no dump
    if [[ "$modo" == "dump" ]]; then
        local header="### \`${rel_path}\`"
        [[ -n "$size_warn" ]] && header="${header}  — ${size_warn}"
        {
            echo ""
            echo "---"
            echo ""
            echo "${header}"
            echo ""
            echo "\`\`\`${lang}"
        } >> "${dump_dest}"

        if cat "${filepath}" >> "${dump_dest}" 2>/dev/null; then
            printf '\n```\n\n' >> "${dump_dest}"
            log "OK: ${rel_path} [${lang}] ${size_kb}KB"
        else
            {
                printf '```\n\n'
                echo "> ⚠ ERRO: sem permissão de leitura em \`${rel_path}\` — arquivo ignorado"
                echo ""
            } >> "${dump_dest}"
            log "ERRO de leitura: ${rel_path}"
        fi
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MODO DRY-RUN (-g -n)
# ══════════════════════════════════════════════════════════════════════════════
if (( DRY_RUN )); then
    # Desativa trap de limpeza — dry-run não cria arquivos
    trap - EXIT INT TERM

    titulo "╔══════════════════════════════════════════════════════════════╗"
    titulo "║  DRY-RUN — arquivos que seriam incluídos no dump             ║"
    titulo "╚══════════════════════════════════════════════════════════════╝"
    [[ -n "$ONLY_SUBDIR" ]] && echo "  Escopo : ${ONLY_SUBDIR}/"
    (( NO_DOCS ))           && echo "  Modo   : -d ativo (docs e Markdown excluídos)"
    echo ""

    COUNT=0; WARN_COUNT=0; BIN_COUNT=0; EST_BYTES=0

    for filepath in "${FILES[@]}"; do
        COUNT=$((COUNT + 1))
        raw_bytes=$(stat -c%s "${filepath}" 2>/dev/null || echo "0")
        EST_BYTES=$(( EST_BYTES + raw_bytes ))

        result=$(processar_arquivo "${filepath}" "dry")
        case "$result" in
            bin)   BIN_COUNT=$((BIN_COUNT + 1)) ;;
            large) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        esac
    done

    # Fator 3.5 para PT-BR
    EST_TOKENS=$(( EST_BYTES * 2 / 7 ))
    LIMIT_MSG=""
    (( MAX_TOKENS > 0 )) && LIMIT_MSG="  (limite: ${MAX_TOKENS})"

    echo ""
    echo "──────────────────────────────────────────────────────────────"
    printf "  Total de arquivos  : %d\n"    "${TOTAL}"
    printf "  Grandes (> %dKB)   : %d\n"    "${MAX_SIZE_KB}" "${WARN_COUNT}"
    printf "  Binários ignorados : %d\n"    "${BIN_COUNT}"
    printf "  Tamanho estimado   : %dKB\n"  "$(( EST_BYTES / 1024 ))"
    printf "  Tokens estimados   : ~%d%s\n" "${EST_TOKENS}" "${LIMIT_MSG}"
    echo "──────────────────────────────────────────────────────────────"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# MODO GERAR (-g)
# ══════════════════════════════════════════════════════════════════════════════
(( ! QUIET )) && echo ""
(( ! QUIET )) && titulo "→ Gerando dump em '${DUMP_FILE}'..."

# Verifica espaço antes de começar a escrever
verificar_espaco

# Info git (falha silenciosa se git não estiver disponível ou não for repositório)
GIT_INFO=""
if command -v git &>/dev/null; then
    if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        GIT_BRANCH="$(git -C "${ROOT_DIR}" branch --show-current 2>/dev/null || echo "detached")"
        GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        GIT_INFO="${GIT_BRANCH} @ ${GIT_COMMIT}"
    fi
fi

EXCLUDED_LIST="${EXCLUDE_DIRS[*]}"

# Cria o dump — a partir daqui o trap de limpeza está ativo
: > "${DUMP_FILE}"
log "Iniciando geração do dump"

# ─── Cabeçalho Markdown ───────────────────────────────────────────────────────
{
    echo "# Dump do Projeto: $(basename "${ROOT_DIR}")"
    echo ""
    echo "| Campo | Valor |"
    echo "|---|---|"
    echo "| **Diretório raiz** | \`${ROOT_DIR}\` |"
    echo "| **Gerado em** | $(date '+%Y-%m-%dT%H:%M:%S%z') |"
    echo "| **Distro** | $(detect_distro) |"
    echo "| **Total de arquivos** | ${TOTAL} |"
    [[ -n "$GIT_INFO" ]] && echo "| **Git** | \`${GIT_INFO}\` |"
    [[ -n "$ONLY_SUBDIR" ]] && echo "| **Escopo** | \`${ONLY_SUBDIR}/\` |"
    (( NO_DOCS ))        && echo "| **Modo** | \`-d\` (docs e Markdown excluídos) |"
    (( MAX_TOKENS > 0 )) && echo "| **Limite tokens** | ${MAX_TOKENS} |"
    echo "| **Excluídos** | \`${EXCLUDED_LIST}\` |"
    echo ""
} >> "${DUMP_FILE}"

# ─── Comentário do desenvolvedor ──────────────────────────────────────────────
if [[ -n "$COMENTARIO" ]]; then
    {
        echo "## Comentário do desenvolvedor"
        echo ""
        echo "> ${COMENTARIO}"
        echo ""
    } >> "${DUMP_FILE}"
fi

# ─── Instruções para retomada por IA ──────────────────────────────────────────
{
    echo "## Instruções para retomada do projeto"
    echo ""
    echo "Este é um dump completo de um projeto. Você está retomando do zero."
    echo ""
    echo "- Leia primeiro a estrutura de diretórios (tree)."
    echo "- Depois leia os arquivos na ordem apresentada."
    echo "- Considere o comentário (se presente) como o último estado mental do desenvolvedor."
    echo "- Pergunte apenas o essencial; evite suposições."
    echo "- Foque em continuar de onde parou."
    echo ""
} >> "${DUMP_FILE}"

# ─── Árvore de diretórios ─────────────────────────────────────────────────────
{
    echo "## Estrutura do Projeto"
    echo ""
    echo '```'
    tree -a --noreport -I "${TREE_EXCLUDE}" "${SEARCH_ROOT}" 2>/dev/null || \
        echo "(tree não disponível ou diretório vazio)"
    echo '```'
    echo ""
    echo "## Conteúdo dos Arquivos"
    echo ""
} >> "${DUMP_FILE}"

log "Árvore de diretórios embutida"

# ─── Loop principal de arquivos ───────────────────────────────────────────────
COUNT=0; SKIP_BIN=0; SKIP_LARGE=0; TOTAL_BYTES=0

for filepath in "${FILES[@]}"; do
    COUNT=$((COUNT + 1))
    raw_bytes=$(stat -c%s "${filepath}" 2>/dev/null || echo "0")
    TOTAL_BYTES=$(( TOTAL_BYTES + raw_bytes ))

    (( ! QUIET )) && printf "\r   Processando: %d/%d — %-55s" \
        "$COUNT" "$TOTAL" "${filepath#"${ROOT_DIR}/"}"

    result=$(processar_arquivo "${filepath}" "dump" "${DUMP_FILE}")
    case "$result" in
        bin)   SKIP_BIN=$((SKIP_BIN + 1)) ;;
        large) SKIP_LARGE=$((SKIP_LARGE + 1)) ;;
    esac
done

(( ! QUIET )) && printf "\r%80s\r" ""

# Fator 3.5 bytes/token (ajustado para PT-BR/UTF-8)
EST_TOKENS=$(( TOTAL_BYTES * 2 / 7 ))
ARQUIVOS_INCLUIDOS=$(( TOTAL - SKIP_BIN ))
log "Arquivos incluídos: ${ARQUIVOS_INCLUIDOS} | Binários: ${SKIP_BIN} | Grandes: ${SKIP_LARGE}"
log "Tokens estimados: ~${EST_TOKENS}"

# ─── Rodapé Markdown ──────────────────────────────────────────────────────────
{
    echo "---"
    echo ""
    echo "## Resumo Final"
    echo ""
    echo "| Campo | Valor |"
    echo "|---|---|"
    echo "| **Arquivos incluídos** | ${ARQUIVOS_INCLUIDOS} |"
    echo "| **Binários ignorados** | ${SKIP_BIN} |"
    echo "| **Arquivos grandes** | ${SKIP_LARGE} (> ${MAX_SIZE_KB}KB, incluídos com aviso) |"
    echo "| **Tamanho total** | $(( TOTAL_BYTES / 1024 ))KB |"
    echo "| **Tokens estimados** | ~${EST_TOKENS} (1 token ≈ 3.5 bytes, ajustado para PT-BR/UTF-8) |"
    echo ""
    echo "## Verificação de Integridade"
    echo ""
    echo "Checksum SHA-256 salvo em: \`${CHECKSUM_FILE}\`"
    echo ""
    echo '```bash'
    echo "# Verificar integridade:"
    echo "./dump_tree.sh -v"
    echo "# Ou diretamente:"
    echo "sha256sum -c ${CHECKSUM_FILE}"
    echo '```'
    echo ""
} >> "${DUMP_FILE}"

sha256sum "${DUMP_FILE}" > "${CHECKSUM_FILE}"
log "Checksum SHA-256 gerado: ${CHECKSUM_FILE}"
flush_log

# Sinaliza ao trap que a geração foi concluída com sucesso — não deve limpar
DUMP_COMPLETO=1

# ─── Resumo no terminal ───────────────────────────────────────────────────────
if (( ! QUIET )); then
    echo ""
    titulo "  Concluído com sucesso!"
    echo ""
    echo -e "  ${C_BOLD}Dump gerado:${C_RESET} ${ROOT_DIR}/${DUMP_FILE}"
    echo -e "  Arquivos incluídos : ${ARQUIVOS_INCLUIDOS}"
    echo -e "  Tokens estimados   : ~${EST_TOKENS}"
    (( SKIP_BIN   > 0 )) && warn "Binários ignorados : ${SKIP_BIN}"
    (( SKIP_LARGE > 0 )) && warn "Arquivos grandes   : ${SKIP_LARGE} (> ${MAX_SIZE_KB}KB)"
    echo ""
    echo "  ────────────────────────────────────────────────────────────"
    echo -e "  ${C_CYAN}1.${C_RESET} Log completo salvo em ${C_BOLD}'${LOG_FILE}'${C_RESET}."
    echo ""
    echo -e "  ${C_CYAN}2.${C_RESET} Verificação de integridade salva em ${C_BOLD}'${CHECKSUM_FILE}'${C_RESET}."
    echo -e "     Para confirmar que o dump não foi alterado: ${C_BOLD}./dump_tree.sh -v${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}3.${C_RESET} Ajuda completa: ${C_BOLD}./dump_tree.sh --help${C_RESET}"
    echo "  ────────────────────────────────────────────────────────────"
    echo ""
fi
