#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  dump_tree.sh — Dump de projeto + árvore de diretórios (formato Markdown)   ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  USO                                                                         ║
# ║    ./dump_tree.sh -g [OPÇÕES]    Gera o dump em .md                          ║
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
# ║    --max-tokens N  Aborta se estimativa de tokens ultrapassar N              ║
# ║                      ex: ./dump_tree.sh -g --max-tokens 100000               ║
# ║                                                                              ║
# ║  EXEMPLOS                                                                    ║
# ║    ./dump_tree.sh -g                          # dump completo                ║
# ║    ./dump_tree.sh -g -n                       # auditar sem gerar            ║
# ║    ./dump_tree.sh -g -t                       # dump com timestamp           ║
# ║    ./dump_tree.sh -g -d -o src                # só src/, sem docs            ║
# ║    ./dump_tree.sh -g -e vendor -e libs        # exclui pastas extras         ║
# ║    ./dump_tree.sh -g --max-tokens 80000       # limita tamanho               ║
# ║    ./dump_tree.sh -g -t -d -o src/xml         # combinado com timestamp      ║
# ║    ./dump_tree.sh -v                          # verificar dump.md            ║
# ║    ./dump_tree.sh -v -t                       # verificar dump com timestamp ║
# ║                                                                              ║
# ║  ARQUIVOS GERADOS                                                            ║
# ║    dump.md           Conteúdo do projeto em Markdown, com árvore no início   ║
# ║    dump.md.sha256    Checksum SHA-256 para verificação                       ║
# ║    dump.log          Log detalhado da execução                               ║
# ║                                                                              ║
# ║  DEPENDÊNCIAS (instaladas automaticamente se ausentes)                       ║
# ║    tree  find  sudo  file  stat  sha256sum  tput                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Cores (apenas para terminal) ─────────────────────────────────────────────
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
        id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
        id_like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
    fi

    case "$id" in
        fedora) echo "fedora"; return ;;
        rhel|centos|almalinux|rocky) echo "rhel"; return ;;
        debian) echo "debian"; return ;;
        ubuntu|linuxmint|pop) echo "ubuntu"; return ;;
        arch|manjaro|endeavouros) echo "arch"; return ;;
        opensuse*|sles) echo "opensuse"; return ;;
    esac

    for token in $id_like; do
        case "$token" in
            fedora|rhel) echo "fedora"; return ;;
            debian|ubuntu) echo "ubuntu"; return ;;
            arch) echo "arch"; return ;;
            suse) echo "opensuse"; return ;;
        esac
    done
    echo "unknown"
}

get_pkg_name() {
    local binary="$1" distro="$2" entry="${PKG_MAP[$binary]:-}"
    [[ -z "$entry" ]] && echo "$binary" && return
    for pair in $entry; do
        local key="${pair%%:*}" pkg="${pair##*:}"
        if [[ "$distro" == "$key"* || "$key" == "$distro"* ]]; then
            echo "$pkg"; return
        fi
    done
    echo "$binary"
}

install_pkg() {
    local pkg="$1" distro="$2"
    echo -e "  ${C_YELLOW}→ Instalando '${pkg}'...${C_RESET}"
    case "$distro" in
        fedora|rhel)  sudo dnf install -y "$pkg" ;;
        ubuntu|debian) sudo apt-get install -y "$pkg" ;;
        arch)          sudo pacman -S --noconfirm "$pkg" ;;
        opensuse)      sudo zypper install -y "$pkg" ;;
        *) erro "Distro não reconhecida. Instale '$pkg' manualmente."; exit 1 ;;
    esac
}

check_and_install_deps() {
    local distro="$(detect_distro)"
    local deps=(tree file sha256sum tput find stat sudo)
    local missing=()

    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done

    (( ${#missing[@]} == 0 )) && return 0

    echo ""
    titulo "  Verificando dependências..."
    echo -e "  Distro detectada : ${C_BOLD}${distro}${C_RESET}"
    warn "Dependências ausentes: ${missing[*]}"
    echo ""
    read -r -p "  Deseja instalar as dependências ausentes agora? [s/N] " resposta
    echo ""

    if [[ "${resposta,,}" != "s" ]]; then
        erro "Dependências não instaladas. O script não pode continuar."
        exit 1
    fi

    for dep in "${missing[@]}"; do
        local pkg="$(get_pkg_name "$dep" "$distro")"
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

# ─── Configuração ──────────────────────────────────────────────────────────────

SCRIPT_NAME="$(basename "$0")"
ROOT_DIR="$(pwd)"
MAX_SIZE_KB=50
MAX_TOKENS=0
MODE=""
DRY_RUN=0
USE_TIMESTAMP=0
NO_DOCS=0
ONLY_SUBDIR=""
COMENTARIO="${COMENTARIO:-}"           # comentário opcional via variável de ambiente

EXCLUDE_DIRS=( "build" ".git" ".cache" "Testing" )
TREE_EXCLUDE="build|.git|.cache|Testing"

# Suporte a opções longas
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)         ARGS+=( "-h" ) ;;
        --max-tokens)   shift; ARGS+=( "-m" "$1" ) ;;
        --max-tokens=*) ARGS+=( "-m" "${1#*=}" ) ;;
        *)              ARGS+=( "$1" ) ;;
    esac
    shift
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# Sem argumentos
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
    echo "    ./dump_tree.sh -g -d -o src      # só src/, sem docs"
    echo "    ./dump_tree.sh -v                # verificar integridade"
    echo ""
    echo -e "  ${C_CYAN}Para instruções detalhadas: ./dump_tree.sh --help${C_RESET}"
    echo ""
    exit 0
fi

# Parse de argumentos
while getopts ":gvhnto:de:m:" opt; do
    case $opt in
        g) MODE="gerar" ;;
        v) MODE="verificar" ;;
        h) MODE="help" ;;
        n) DRY_RUN=1 ;;
        t) USE_TIMESTAMP=1 ;;
        d) NO_DOCS=1 ;;
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

if [[ "$MODE" == "help" ]]; then
    grep "^# ║" "$0" | sed 's/^# //'
    exit 0
fi

if [[ -z "$MODE" ]]; then
    erro "Nenhum modo especificado. Use -g para gerar ou -v para verificar."
    erro "Para instruções: ./dump_tree.sh --help"
    exit 1
fi

# Nomes dos arquivos
if (( USE_TIMESTAMP )); then
    TS="$(date '+%Y%m%d_%H%M')"
    DUMP_FILE="dump_${TS}.md"
    LOG_FILE="dump_${TS}.log"
else
    DUMP_FILE="dump.md"
    LOG_FILE="dump.log"
fi
CHECKSUM_FILE="${DUMP_FILE}.sha256"

# Modo verificar
if [[ "$MODE" == "verificar" ]]; then
    titulo "╔══════════════════════════════════════════════════════════════╗"
    titulo "║  VERIFICAÇÃO DE INTEGRIDADE SHA-256                          ║"
    titulo "╚══════════════════════════════════════════════════════════════╝"
    echo "  Dump     : ${DUMP_FILE}"
    echo "  Checksum : ${CHECKSUM_FILE}"
    echo ""

    [[ ! -f "${DUMP_FILE}" ]]     && erro "Arquivo '${DUMP_FILE}' não encontrado."     && exit 1
    [[ ! -f "${CHECKSUM_FILE}" ]] && erro "Arquivo '${CHECKSUM_FILE}' não encontrado." \
                                  && erro "Gere o dump novamente com -g." && exit 1

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

# Valida subdiretório
if [[ -n "$ONLY_SUBDIR" && ! -d "${ROOT_DIR}/${ONLY_SUBDIR}" ]]; then
    erro "Subpasta '${ONLY_SUBDIR}' não encontrada em ${ROOT_DIR}."
    exit 1
fi

# Detecção se é projeto
if [[ "$MODE" == "gerar" ]]; then
    high_signals=0 medium_signals=0 low_signals=0

    if [[ -d ".git" ]] || ls CMakeLists.txt Makefile meson.build build.gradle pom.xml package.json Cargo.toml pyproject.toml setup.py composer.json 2>/dev/null | grep -q .; then
        ((high_signals++))
    fi

    if find . -maxdepth 3 -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.rs" -o -name "*.go" -o -name "*.java" -o -name "*.sh" \) -print -quit | grep -q .; then
        ((medium_signals++))
    fi

    if ls README.md LICENSE 2>/dev/null | grep -q .; then
        ((low_signals++))
    fi

    if (( high_signals >= 1 )); then
        : # Prossegue silenciosamente
    elif (( medium_signals || low_signals )); then
        warn "Esta pasta parece ser um projeto parcial (sinais médios ou baixos detectados)."
        read -r -p "  Deseja continuar? [s/N] " resposta
        if [[ "${resposta,,}" != "s" ]]; then
            erro "Operação cancelada."
            exit 1
        fi
    else
        erro "Esta pasta não parece ser um projeto (nenhum sinal detectado)."
        read -r -p "  Deseja continuar mesmo assim? [s/N] " resposta
        if [[ "${resposta,,}" != "s" ]]; then
            erro "Operação cancelada."
            exit 1
        fi
    fi
fi

# Detecta linguagem
detect_language() {
    case "${1,,}" in
        *.cpp|*.cc|*.cxx)       echo "cpp" ;;
        *.c)                    echo "c" ;;
        *.h|*.hpp|*.hxx)        echo "cpp" ;;
        *.cmake|cmakelists.txt) echo "cmake" ;;
        *.sh|*.bash)            echo "bash" ;;
        *.py)                   echo "python" ;;
        *.md)                   echo "markdown" ;;
        *.xml)                  echo "xml" ;;
        *.json)                 echo "json" ;;
        *.yaml|*.yml)           echo "yaml" ;;
        *.txt)                  echo "text" ;;
        *.log)                  echo "text" ;;
        *)                      echo "text" ;;
    esac
}

# Monta exclusões para find
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

declare -a FIND_EXCLUDES=()
build_find_excludes FIND_EXCLUDES

SEARCH_ROOT="${ROOT_DIR}"
[[ -n "$ONLY_SUBDIR" ]] && SEARCH_ROOT="${ROOT_DIR}/${ONLY_SUBDIR}"

mapfile -t FILES < <(
    find "${SEARCH_ROOT}" \
        "${FIND_EXCLUDES[@]}" \
        -type f -size +0c -print \
    | sort
)

TOTAL=${#FILES[@]}
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
        echo "============================================================"
        echo ""
        for entry in "${LOG_ENTRIES[@]}"; do echo "  ${entry}"; done
        echo ""
        echo "============================================================"
        echo "  FIM DO LOG"
        echo "============================================================"
    } >> "${LOG_FILE}"
}

# Estimativa prévia de tokens
if (( MAX_TOKENS > 0 )); then
    EST_BYTES_PRE=0
    for fp in "${FILES[@]}"; do
        EST_BYTES_PRE=$(( EST_BYTES_PRE + $(stat -c%s "${fp}") ))
    done
    EST_TOKENS_PRE=$(( EST_BYTES_PRE / 4 ))
    log "Estimativa de tokens (pré-geração): ~${EST_TOKENS_PRE}"

    if (( EST_TOKENS_PRE > MAX_TOKENS )); then
        erro "Estimativa de tokens (~${EST_TOKENS_PRE}) ultrapassa o limite (${MAX_TOKENS})."
        erro "Reduza o escopo com -o <subpasta>, -d ou -e <pasta> e tente novamente."
        exit 3
    fi
fi

# Modo dry-run
if (( DRY_RUN )); then
    titulo "╔══════════════════════════════════════════════════════════════╗"
    titulo "║  DRY-RUN — arquivos que seriam incluídos no dump             ║"
    titulo "╚══════════════════════════════════════════════════════════════╝"
    [[ -n "$ONLY_SUBDIR" ]] && echo "  Escopo : ${ONLY_SUBDIR}/"
    (( NO_DOCS ))           && echo "  Modo   : -d ativo (docs e Markdown excluídos)"
    echo ""

    COUNT=0; WARN_COUNT=0; BIN_COUNT=0; EST_BYTES=0

    for filepath in "${FILES[@]}"; do
        COUNT=$((COUNT + 1))
        rel_path="${filepath#"${ROOT_DIR}/"}"
        lang=$(detect_language "$(basename "${filepath}")")
        raw_bytes=$(stat -c%s "${filepath}")
        size_kb=$(( (raw_bytes + 1023) / 1024 ))
        EST_BYTES=$(( EST_BYTES + raw_bytes ))

        if ! file --mime-type "${filepath}" | grep -qE 'text/|xml|json|x-empty'; then
            BIN_COUNT=$((BIN_COUNT + 1))
            echo -e "${C_YELLOW}  [BINÁRIO  ]${C_RESET} ${rel_path}"
            continue
        fi

        if (( size_kb > MAX_SIZE_KB )); then
            WARN_COUNT=$((WARN_COUNT + 1))
            printf "${C_YELLOW}  [⚠ %4dKB]${C_RESET} %-52s [%s]\n" \
                "${size_kb}" "${rel_path}" "${lang}"
        else
            printf "  [  %4dKB] %-52s [%s]\n" "${size_kb}" "${rel_path}" "${lang}"
        fi
    done

    EST_TOKENS=$(( EST_BYTES / 4 ))
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

# Geração do dump
echo ""
titulo "→ Gerando dump em '${DUMP_FILE}'..."

: > "${DUMP_FILE}"
log "Iniciando geração do dump"

# Lista de excluídos para cabeçalho
EXCLUSAO_PADRAO="build/ .git/ .cache/ Testing/"
EXCLUSAO_EXTRA=""
if (( ${#EXCLUDE_DIRS[@]} > 4 )); then
    EXCLUSAO_EXTRA=" + personalizadas via -e: ${EXCLUDE_DIRS[*]:4}"
fi

# Último commit e branch (se git existir)
GIT_INFO=""
if [[ -d ".git" ]]; then
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "não disponível")
    BRANCH_ATUAL=$(git branch --show-current 2>/dev/null || echo "não disponível")
    GIT_INFO="Último commit: ${COMMIT_HASH} | Branch: ${BRANCH_ATUAL}"
fi

{
    echo "# Dump do Projeto: $(basename "${ROOT_DIR}")"
    echo "Diretório raiz: ${ROOT_DIR}"
    echo "Gerado em (ISO): $(date --iso-8601=seconds)"
    echo "Distro        : $(detect_distro)"
    [[ -n "$ONLY_SUBDIR" ]] && echo "Escopo        : ${ONLY_SUBDIR}/"
    (( NO_DOCS ))           && echo "Modo          : -d (docs e Markdown excluídos)"
    (( MAX_TOKENS > 0 ))    && echo "Limite tokens : ${MAX_TOKENS}"
    echo "Total arquivos: ${TOTAL}"
    echo "Excluídos automaticamente: ${EXCLUSAO_PADRAO}${EXCLUSAO_EXTRA}"
    if [[ -n "$GIT_INFO" ]]; then
        echo "${GIT_INFO}"
    fi
    if [[ -n "$COMENTARIO" ]]; then
        echo "Comentário    : ${COMENTARIO}"
    fi
    echo ""

    echo "## Instruções para retomada do projeto"
    echo "Este é um dump completo de um projeto. Você está retomando do zero."
    echo "- Leia primeiro a estrutura de diretórios (tree)."
    echo "- Depois leia os arquivos na ordem apresentada ou que fizer sentido."
    echo "- Considere o comentário (se houver) como o último estado mental do desenvolvedor."
    echo "- Pergunte apenas o essencial; evite suposições desnecessárias."
    echo "- Foque em continuar exatamente de onde parou."
    echo ""

    echo "## Estrutura do Projeto (tree)"
    echo ""
    echo '```'
    tree -a --du -s -h -p -D -I "${TREE_EXCLUDE}" --noreport "${SEARCH_ROOT}"
    echo '```'
    echo ""
    echo "## Conteúdo dos Arquivos"
    echo ""
} >> "${DUMP_FILE}"

log "Cabeçalho e árvore incluídos"

COUNT=0; SKIP_BIN=0; SKIP_LARGE=0; TOTAL_BYTES=0; TOTAL_LINHAS=0; PRIMEIRO_ARQUIVO=1

for filepath in "${FILES[@]}"; do
    COUNT=$((COUNT + 1))
    rel_path="${filepath#"${ROOT_DIR}/"}"
    lang=$(detect_language "$(basename "${filepath}")")
    raw_bytes=$(stat -c%s "${filepath}")
    size_kb=$(( (raw_bytes + 1023) / 1024 ))
    TOTAL_BYTES=$(( TOTAL_BYTES + raw_bytes ))

    printf "\r   Processando: %d/%d — %-55s" "$COUNT" "$TOTAL" "${rel_path:0:55}"

    if ! file --mime-type "${filepath}" | grep -qE 'text/|xml|json|x-empty'; then
        SKIP_BIN=$((SKIP_BIN + 1))
        tipo=$(file -b "${filepath}" 2>/dev/null | head -c 80)  # descrição curta
        tamanho=$(stat -c%s "${filepath}" 2>/dev/null || echo "?")
        log "BINÁRIO ignorado: ${rel_path} (${tipo}, ${tamanho} bytes)"

        {
            if [[ $PRIMEIRO_ARQUIVO -eq 1 ]]; then
                PRIMEIRO_ARQUIVO=0
            else
                echo "---"
                echo ""
            fi
            echo "### ${rel_path}  [BINÁRIO — IGNORADO]"
            echo "Tipo detectado : ${tipo}"
            echo "Tamanho        : ${tamanho} bytes"
            echo ""
        } >> "${DUMP_FILE}"
        continue
    fi

    SIZE_WARN=""
    if (( size_kb > MAX_SIZE_KB )); then
        SKIP_LARGE=$((SKIP_LARGE + 1))
        SIZE_WARN="  ⚠ ARQUIVO GRANDE: ${size_kb}KB"
        log "ARQUIVO GRANDE (${size_kb}KB): ${rel_path}"
    fi

    {
        if [[ $PRIMEIRO_ARQUIVO -eq 1 ]]; then
            PRIMEIRO_ARQUIVO=0
        else
            echo "---"
            echo ""
        fi
        echo "### ${rel_path}${SIZE_WARN}"
        echo ""
        echo '```'"${lang}"
        if sudo cat "${filepath}" >> "${DUMP_FILE}" 2>/dev/null; then
            linhas=$(wc -l < "${filepath}" 2>/dev/null || echo 0)
            TOTAL_LINHAS=$((TOTAL_LINHAS + linhas))
        else
            echo "[ERRO: não foi possível ler '${rel_path}']"
            linhas=0
        fi
        echo '```'
        echo ""
    } >> "${DUMP_FILE}"

    log "OK: ${rel_path} [${lang}] ${size_kb}KB"
done

printf "\r%80s\r" ""

EST_TOKENS=$(( TOTAL_BYTES / 4 ))
ARQUIVOS_INCLUIDOS=$(( TOTAL - SKIP_BIN ))
log "Arquivos incluídos: ${ARQUIVOS_INCLUIDOS} | Binários ignorados: ${SKIP_BIN} | Grandes: ${SKIP_LARGE}"
log "Tokens estimados: ~${EST_TOKENS}"

{
    echo "## Resumo Final"
    echo "Arquivos incluídos     : ${ARQUIVOS_INCLUIDOS}"
    echo "Binários ignorados     : ${SKIP_BIN}"
    echo "Arquivos grandes       : ${SKIP_LARGE} (> ${MAX_SIZE_KB}KB)"
    echo "Tamanho total fonte    : $(( TOTAL_BYTES / 1024 )) KB"
    echo "Linhas totais aproximadas: ${TOTAL_LINHAS}"
    echo "Tokens estimados       : ~${EST_TOKENS}  (estimativa: 1 token ≈ 4 bytes)"
    echo ""
    echo "## Verificação de Integridade"
    echo "Um checksum SHA-256 deste dump foi salvo em:"
    echo "  ${CHECKSUM_FILE}"
    echo ""
    echo "Para verificar a integridade deste arquivo, execute:"
    echo "  ./dump_tree.sh -v"
    [[ "$DUMP_FILE" != "dump.md" ]] && \
    echo "  ./dump_tree.sh -v -t   (dump gerado com timestamp)"
    echo ""
    echo "Ou diretamente via sha256sum:"
    echo "  sha256sum -c ${CHECKSUM_FILE}"
    echo ""
    echo "Saída esperada:  ${DUMP_FILE}: OK"
    echo "Se retornar FAILED, o arquivo foi alterado e não é confiável."
} >> "${DUMP_FILE}"

sha256sum "${DUMP_FILE}" > "${CHECKSUM_FILE}"
log "Checksum SHA-256 gerado: ${CHECKSUM_FILE}"
flush_log

# ─── Resumo no terminal ───────────────────────────────────────────────────────
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
echo -e "  ${C_CYAN}1.${C_RESET} Um log completo desta execução foi salvo em ${C_BOLD}'${LOG_FILE}'${C_RESET}."
echo    "     Abra-o para inspecionar quais arquivos foram incluídos, ignorados ou apresentaram erro."
echo ""
echo -e "  ${C_CYAN}2.${C_RESET} Um arquivo de verificação de integridade foi salvo em ${C_BOLD}'${CHECKSUM_FILE}'${C_RESET}."
echo -e "     Sempre que quiser confirmar que o dump não foi alterado, execute:"
echo -e "     ${C_BOLD}./dump_tree.sh -v${C_RESET}"
echo ""
echo -e "  ${C_CYAN}3.${C_RESET} Não sabe o que fazer a seguir ou precisa de ajuda com as opções disponíveis?"
echo -e "     Digite ${C_BOLD}./dump_tree.sh --help${C_RESET} para ver todos os comandos e exemplos de uso."
echo "  ────────────────────────────────────────────────────────────"
echo ""
