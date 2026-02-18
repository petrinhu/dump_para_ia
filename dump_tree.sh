#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  dump_tree.sh — Dump de projeto + árvore de diretórios (formato Markdown)   ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  USO                                                                         ║
# ║    ./dump_tree.sh -g [OPÇÕES]    Gera o dump em .md                          ║
# ║    ./dump_tree.sh -v [-t]        Verifica integridade do dump                ║
# ║    ./dump_tree.sh -h             Exibe esta ajuda                            ║
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

    titulo "  Verificando dependências..."
    echo -e "  Distro detectada : ${C_BOLD}${distro}${C_RESET}"
    warn "Dependências ausentes: ${missing[*]}"
    read -r -p "  Deseja instalar as dependências ausentes agora? [s/N] " resposta
    [[ "${resposta,,}" != "s" ]] && erro "Dependências necessárias. Abortando." && exit 1

    for dep in "${missing[@]}"; do
        local pkg="$(get_pkg_name "$dep" "$distro")"
        install_pkg "$pkg" "$distro"
        command -v "$dep" &>/dev/null || { erro "Falha ao instalar $dep"; exit 1; }
        info "$dep instalado."
    done
    info "Dependências ok."
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
COMENTARIO="${COMENTARIO:-}"

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
    titulo "  dump_tree.sh — Dump de projeto + árvore de diretórios"
    echo ""
    echo "  MODOS DISPONÍVEIS:"
    echo "    -g            Gera o dump completo do projeto"
    echo "    -g -n         Dry-run: audita arquivos sem gerar dump"
    echo "    -v            Verifica integridade do dump gerado"
    echo "    -h / --help   Exibe a ajuda completa"
    echo ""
    echo "  Exemplos rápidos:"
    echo "    ./dump_tree.sh -g -t             # dump com timestamp"
    echo "    ./dump_tree.sh -g -n             # auditar sem gerar"
    echo ""
    exit 0
fi

# Parse de opções
while getopts ":gvhnto:de:m:" opt; do
    case $opt in
        g) MODE="gerar" ;;
        v) MODE="verificar" ;;
        h) MODE="help" ;;
        n) DRY_RUN=1 ;;
        t) USE_TIMESTAMP=1 ;;
        d) NO_DOCS=1 ;;
        o) ONLY_SUBDIR="$OPTARG" ;;
        e) EXCLUDE_DIRS+=( "$OPTARG" ); TREE_EXCLUDE="${TREE_EXCLUDE}|${OPTARG}" ;;
        m) MAX_TOKENS="$OPTARG" ;;
        :) erro "Opção -${OPTARG} requer argumento."; exit 1 ;;
        *) erro "Opção desconhecida: -${OPTARG}"; exit 1 ;;
    esac
done

shift $((OPTIND-1))

# Verifica argumentos extras inválidos
if [[ $# -gt 0 ]]; then
    erro "Argumentos inválidos após opções: $*"
    erro "Execute ./dump_tree.sh -h para ajuda"
    exit 1
fi

if [[ "$MODE" == "help" ]]; then
    grep "^# ║" "$0" | sed 's/^# //'
    exit 0
fi

if [[ -z "$MODE" ]]; then
    erro "Nenhum modo especificado. Use -g para gerar ou -v para verificar."
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
    titulo "VERIFICAÇÃO DE INTEGRIDADE"
    echo "  Arquivo: ${DUMP_FILE}"
    echo "  Checksum: ${CHECKSUM_FILE}"
    [[ ! -f "$DUMP_FILE" ]] && erro "Dump não encontrado" && exit 1
    [[ ! -f "$CHECKSUM_FILE" ]] && erro "Checksum não encontrado" && exit 1
    if sha256sum -c "$CHECKSUM_FILE" 2>/dev/null; then
        info "Integridade confirmada."
    else
        erro "DUMP ALTERADO — gere novamente com -g"
        exit 2
    fi
    exit 0
fi

# Valida subdiretório
if [[ -n "$ONLY_SUBDIR" && ! -d "${ROOT_DIR}/${ONLY_SUBDIR}" ]]; then
    erro "Subpasta '${ONLY_SUBDIR}' não existe."
    exit 1
fi

# Detecção se é projeto (com saída mais clara)
if [[ "$MODE" == "gerar" ]]; then
    high_signals=0 medium_signals=0 low_signals=0

    [[ -d ".git" ]] && ((high_signals++))
    ls CMakeLists.txt Makefile package.json Cargo.toml pyproject.toml 2>/dev/null && ((high_signals++))
    find . -maxdepth 3 -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.sh" \) -print -quit 2>/dev/null && ((medium_signals++))
    ls README.md LICENSE 2>/dev/null && ((low_signals++))

    if (( high_signals >= 1 )); then
        info "Projeto detectado (sinal alto: .git ou build system)"
    elif (( medium_signals || low_signals )); then
        warn "Projeto parcial detectado (sinais médios/baixos)"
        read -r -p "  Continuar mesmo assim? [s/N] " r
        [[ "${r,,}" != "s" ]] && erro "Cancelado." && exit 1
    else
        erro "Nenhum sinal de projeto detectado (sem .git, README, código fonte...)"
        read -r -p "  Continuar mesmo assim? [s/N] " r
        [[ "${r,,}" != "s" ]] && erro "Cancelado." && exit 1
    fi
fi

# Detecta linguagem
detect_language() {
    case "${1,,}" in
        *.sh|*.bash) echo "bash" ;;
        *.md) echo "markdown" ;;
        *.yaml|*.yml) echo "yaml" ;;
        *.json) echo "json" ;;
        *.txt) echo "text" ;;
        *) echo "text" ;;
    esac
}

# Monta exclusões
build_find_excludes() {
    local -n arr=$1
    arr=()
    local root="${ROOT_DIR}"
    [[ -n "$ONLY_SUBDIR" ]] && root="${ROOT_DIR}/${ONLY_SUBDIR}"

    for d in "${EXCLUDE_DIRS[@]}"; do
        arr+=( -path "${root}/${d}" -prune -o )
    done
    arr+=( -path "${ROOT_DIR}/${DUMP_FILE}"     -prune -o )
    arr+=( -path "${ROOT_DIR}/${CHECKSUM_FILE}" -prune -o )
    arr+=( -path "${ROOT_DIR}/${LOG_FILE}"      -prune -o )
    arr+=( -path "${ROOT_DIR}/${SCRIPT_NAME}"   -prune -o )

    if (( NO_DOCS )); then
        arr+=( -path "${root}/docs" -prune -o )
        arr+=( -name "*.md" -prune -o )
        arr+=( -name "LICENSE" -prune -o )
        arr+=( -name "CHANGELOG*" -prune -o )
    fi
}

declare -a FIND_EXCLUDES=()
build_find_excludes FIND_EXCLUDES

SEARCH_ROOT="${ROOT_DIR}"
[[ -n "$ONLY_SUBDIR" ]] && SEARCH_ROOT="${ROOT_DIR}/${ONLY_SUBDIR}"

mapfile -t FILES < <(find "${SEARCH_ROOT}" "${FIND_EXCLUDES[@]}" -type f -size +0c -print | sort)

TOTAL=${#FILES[@]}
LOG_ENTRIES=()
log() { LOG_ENTRIES+=("$(date '+%H:%M:%S') $*"); }

if (( TOTAL == 0 )); then
    warn "Nenhum arquivo textual encontrado para dump."
    warn "Possíveis causas:"
    warn "  - Diretório vazio ou só com binários"
    warn "  - Todas as pastas excluídas via -e ou -d"
    warn "  - Arquivos não são texto (verificados por 'file --mime-type')"
    if (( DRY_RUN )); then
        exit 0
    else
        erro "Dump vazio. Abortando geração."
        exit 1
    fi
fi

flush_log() {
    : > "$LOG_FILE"
    {
        echo "LOG DE EXECUÇÃO - dump_tree.sh"
        echo "Projeto     : $ROOT_DIR"
        echo "Data        : $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Distro      : $(detect_distro)"
        echo "Dump gerado : $DUMP_FILE"
        [[ -n "$ONLY_SUBDIR" ]] && echo "Escopo      : ${ONLY_SUBDIR}/"
        (( NO_DOCS )) && echo "Modo        : -d ativo"
        (( MAX_TOKENS > 0 )) && echo "Limite      : $MAX_TOKENS tokens"
        echo ""
        for e in "${LOG_ENTRIES[@]}"; do echo "  $e"; done
        echo ""
        echo "FIM DO LOG"
    } >> "$LOG_FILE"
}

# Estimativa tokens
if (( MAX_TOKENS > 0 )); then
    EST_BYTES=0
    for f in "${FILES[@]}"; do
        EST_BYTES=$((EST_BYTES + $(stat -c%s "$f")))
    done
    EST_TOKENS=$((EST_BYTES / 4))
    log "Estimativa prévia: ~$EST_TOKENS tokens"
    (( EST_TOKENS > MAX_TOKENS )) && erro "Excede limite ($EST_TOKENS > $MAX_TOKENS)" && exit 3
fi

# Modo dry-run
if (( DRY_RUN )); then
    titulo "DRY-RUN — arquivos que seriam incluídos"
    [[ -n "$ONLY_SUBDIR" ]] && echo "Escopo: ${ONLY_SUBDIR}/"
    (( NO_DOCS )) && echo "Modo -d ativo"
    echo ""
    echo "Total arquivos encontrados: $TOTAL"
    echo ""

    COUNT=0 WARN_COUNT=0 BIN_COUNT=0 EST_BYTES=0
    for fp in "${FILES[@]}"; do
        ((COUNT++))
        rel="${fp#"$ROOT_DIR"/}"
        lang=$(detect_language "$(basename "$fp")")
        size=$(stat -c%s "$fp")
        kb=$(( (size + 1023) / 1024 ))
        EST_BYTES=$((EST_BYTES + size))

        if ! file --mime-type "$fp" | grep -qE 'text/|xml|json|x-empty'; then
            ((BIN_COUNT++))
            echo -e "${C_YELLOW}  [BIN] ${rel}${C_RESET}"
            continue
        fi

        if (( kb > MAX_SIZE_KB )); then
            ((WARN_COUNT++))
            printf "${C_YELLOW}  [> %dKB] %-50s [%s]\n${C_RESET}" "$kb" "$rel" "$lang"
        else
            printf "  [%6dKB] %-50s [%s]\n" "$kb" "$rel" "$lang"
        fi
    done

    echo ""
    echo "──────────────────────────────────────────────"
    printf "Total arquivos     : %d\n" "$TOTAL"
    printf "Grandes (>50KB)    : %d\n" "$WARN_COUNT"
    printf "Binários ignorados : %d\n" "$BIN_COUNT"
    printf "Tamanho estimado   : %d KB\n" "$((EST_BYTES / 1024))"
    printf "Tokens estimados   : ~%d\n" "$((EST_BYTES / 4))"
    echo "──────────────────────────────────────────────"
    exit 0
fi

# Geração do dump
echo ""
titulo "→ Gerando dump em '${DUMP_FILE}'..."
echo "Opções ativas:"
[[ -n "$ONLY_SUBDIR" ]] && echo "  - Escopo: ${ONLY_SUBDIR}/"
(( NO_DOCS )) && echo "  - Excluindo docs/Markdown"
(( USE_TIMESTAMP )) && echo "  - Timestamp ativo"
(( MAX_TOKENS > 0 )) && echo "  - Limite tokens: ${MAX_TOKENS}"
echo "Arquivos encontrados: ${TOTAL}"
echo ""

: > "$DUMP_FILE"
log "Início da geração"

{
    echo "# Dump do Projeto: $(basename "$ROOT_DIR")"
    echo "Diretório raiz: $ROOT_DIR"
    echo "Gerado em (ISO): $(date --iso-8601=seconds)"
    echo "Distro        : $(detect_distro)"
    [[ -n "$ONLY_SUBDIR" ]] && echo "Escopo        : ${ONLY_SUBDIR}/"
    (( NO_DOCS ))           && echo "Modo          : -d (docs excluídos)"
    (( MAX_TOKENS > 0 ))    && echo "Limite tokens : ${MAX_TOKENS}"
    echo "Total arquivos: ${TOTAL}"
    if [[ -n "$COMENTARIO" ]]; then
        echo "Comentário    : ${COMENTARIO}"
    fi
    echo ""
    echo "## Estrutura do Projeto (tree)"
    echo ""
    echo '```'
    tree -a --du -s -h -p -D -I "$TREE_EXCLUDE" --noreport "$SEARCH_ROOT"
    echo '```'
    echo ""
    echo "## Conteúdo dos Arquivos"
    echo ""
} >> "$DUMP_FILE"

log "Árvore de diretórios incluída"

COUNT=0; SKIP_BIN=0; SKIP_LARGE=0; TOTAL_BYTES=0; TOTAL_LINHAS=0; PRIMEIRO_ARQUIVO=1

for filepath in "${FILES[@]}"; do
    ((COUNT++))
    rel_path="${filepath#"$ROOT_DIR"/}"
    lang=$(detect_language "$(basename "$filepath")")
    size=$(stat -c%s "$filepath")
    kb=$(( (size + 1023) / 1024 ))
    TOTAL_BYTES=$((TOTAL_BYTES + size))

    printf "\rProcessando %d/%d  %-55s" "$COUNT" "$TOTAL" "${rel_path:0:55}"

    if ! file --mime-type "$filepath" | grep -qE 'text/|xml|json|x-empty'; then
        SKIP_BIN=$((SKIP_BIN + 1))
        tipo=$(file -b "$filepath" 2>/dev/null | head -c 80)
        tamanho=$(stat -c%s "$filepath" 2>/dev/null || echo "?")
        log "BINÁRIO ignorado: $rel_path ($tipo, $tamanho bytes)"

        {
            if (( PRIMEIRO_ARQUIVO == 1 )); then
                PRIMEIRO_ARQUIVO=0
            else
                echo "---"
                echo ""
            fi
            echo "### $rel_path  [BINÁRIO — IGNORADO]"
            echo "Tipo detectado : $tipo"
            echo "Tamanho        : $tamanho bytes"
            echo ""
        } >> "$DUMP_FILE"
        continue
    fi

    SIZE_WARN=""
    if (( kb > MAX_SIZE_KB )); then
        SKIP_LARGE=$((SKIP_LARGE + 1))
        SIZE_WARN="  ⚠ ARQUIVO GRANDE: ${kb}KB"
        log "Arquivo grande (${kb}KB): $rel_path"
    fi

    {
        if (( PRIMEIRO_ARQUIVO == 1 )); then
            PRIMEIRO_ARQUIVO=0
        else
            echo "---"
            echo ""
        fi
        echo "### $rel_path${SIZE_WARN}"
        echo ""
        echo '```'"$lang"
        if sudo cat "$filepath" >> "$DUMP_FILE" 2>/dev/null; then
            linhas=$(wc -l < "$filepath" 2>/dev/null || echo 0)
            TOTAL_LINHAS=$((TOTAL_LINHAS + linhas))
        else
            echo "[ERRO: não foi possível ler '$rel_path']"
            linhas=0
        fi
        echo '```'
        echo ""
    } >> "$DUMP_FILE"

    log "OK: $rel_path [$lang] ${kb}KB"
done

printf "\r%80s\r" ""

EST_TOKENS=$(( TOTAL_BYTES / 4 ))
ARQUIVOS_INCLUIDOS=$(( TOTAL - SKIP_BIN ))

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
    echo "Checksum SHA-256 salvo em: ${CHECKSUM_FILE}"
    echo ""
    echo "Para verificar:"
    echo "  ./dump_tree.sh -v"
    [[ "$DUMP_FILE" != "dump.md" ]] && \
    echo "  ./dump_tree.sh -v -t   (com timestamp)"
    echo ""
    echo "Ou:"
    echo "  sha256sum -c ${CHECKSUM_FILE}"
    echo ""
    echo "Saída OK = dump íntegro."
    echo "FAILED = arquivo alterado → gere novamente."
} >> "$DUMP_FILE"

sha256sum "$DUMP_FILE" > "$CHECKSUM_FILE"
log "Checksum gerado: $CHECKSUM_FILE"
flush_log

titulo "  Concluído!"
echo ""
echo -e "  Dump gerado: ${C_BOLD}${ROOT_DIR}/${DUMP_FILE}${C_RESET}"
echo "  Arquivos incluídos : $ARQUIVOS_INCLUIDOS"
echo "  Tokens estimados   : ~$EST_TOKENS"
(( SKIP_BIN   > 0 )) && warn "Binários ignorados : $SKIP_BIN"
(( SKIP_LARGE > 0 )) && warn "Arquivos grandes   : $SKIP_LARGE (>50KB)"
echo ""
echo "  Log detalhado: ${C_BOLD}${LOG_FILE}${C_RESET}"
echo "  Checksum     : ${C_BOLD}${CHECKSUM_FILE}${C_RESET}"
echo ""
echo -e "  ${C_CYAN}Verificar integridade:${C_RESET} ./dump_tree.sh -v"
echo ""
