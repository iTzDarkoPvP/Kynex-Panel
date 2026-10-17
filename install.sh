#!/usr/bin/env bash
# ==============================================================================
#  Kynex Panel · Instalador automático
#
#  Uso:   sudo bash install.sh
#
#  Pon este archivo DENTRO de la carpeta del panel (donde están server.js,
#  index.html, package.json, mailer.js, ddos-blocked.js, etc.) y ejecútalo.
#
#  Qué hace:
#    1. Instala lo necesario (Node.js 20, PM2, compiladores, iptables, zip, ...)
#    2. Copia el panel a /opt/kynex-panel e instala sus dependencias
#    3. (Opcional) Saca un certificado SSL gratis con Certbot y lo renueva solo
#    4. Lo deja corriendo 24/7 con PM2 y arranca solo al reiniciar la VPS
#    5. Crea tu usuario administrador principal
#
#  Sistemas soportados: Ubuntu 20.04+ y Debian 11+ (con root).
#
#  Modo automático (sin preguntas), por si lo quieres usar en un script:
#    KYNEX_USER=admin KYNEX_PASS='MiClaveSegura1' KYNEX_SSL=n sudo -E bash install.sh
#  Variables: KYNEX_USER KYNEX_PASS KYNEX_EMAIL KYNEX_SSL(y/n) KYNEX_DOMAIN
#             KYNEX_LE_EMAIL KYNEX_PORT KYNEX_SSL_PORT KYNEX_JAVA(y/n)
#             KYNEX_SMTP(y/n) KYNEX_SMTP_HOST/PORT/USER/PASS/FROM  INSTALL_DIR
# ==============================================================================
set -Eeuo pipefail
umask 022

APP_NAME="kynex-panel"
INSTALL_DIR="${INSTALL_DIR:-/opt/kynex-panel}"
LOG_FILE="${KYNEX_LOG:-/var/log/kynex-install.log}"
NODE_MAJOR=20
MIN_NODE=18
MIN_PASS=8
GAME_PORT_MIN=19132
GAME_PORT_MAX=26000
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SELF_NAME="$(basename -- "${BASH_SOURCE[0]:-$0}")"

# ------------------------------------------------------------------ colores ---
if [ -t 1 ]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_CYN=$'\e[36m'
  C_DIM=$'\e[2m'; C_BLD=$'\e[1m'; C_OFF=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_CYN=""; C_DIM=""; C_BLD=""; C_OFF=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
ok()   { printf '  %s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YLW" "$C_OFF" "$*"; }
step() { printf '\n%s%s▸ %s%s\n' "$C_BLD" "$C_CYN" "$*" "$C_OFF"; }
die()  {
  printf '\n  %s✘ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
  printf '  %sRevisa el registro completo en: %s%s\n\n' "$C_DIM" "$LOG_FILE" "$C_OFF" >&2
  exit 1
}

on_error() {
  local code=$? line=${1:-?}
  printf '\n  %s✘ El instalador se detuvo (línea %s, código %s).%s\n' "$C_RED" "$line" "$code" "$C_OFF" >&2
  printf '  %sRegistro completo: %s%s\n' "$C_DIM" "$LOG_FILE" "$C_OFF" >&2
  printf '  %sPuedes volver a ejecutar el instalador: es seguro repetirlo.%s\n\n' "$C_DIM" "$C_OFF" >&2
}
trap 'on_error $LINENO' ERR

# ----------------------------------------------------------- ejecutar + log ---
# run "mensaje" comando args...   (si falla, corta la instalación mostrando el final del log)
run() {
  local msg="$1"; shift
  printf '  %s…%s %s' "$C_DIM" "$C_OFF" "$msg"
  if "$@" >>"$LOG_FILE" 2>&1; then
    printf '\r\033[K  %s✔%s %s\n' "$C_GRN" "$C_OFF" "$msg"
  else
    printf '\r\033[K  %s✘%s %s\n' "$C_RED" "$C_OFF" "$msg"
    printf '\n%s--- últimas líneas del registro ---%s\n' "$C_DIM" "$C_OFF" >&2
    tail -n 15 "$LOG_FILE" >&2 || true
    die "Falló: $msg"
  fi
}
# soft: igual que run pero no corta (devuelve 0 si salió bien, 1 si falló)
soft() {
  local msg="$1"; shift
  printf '  %s…%s %s' "$C_DIM" "$C_OFF" "$msg"
  if "$@" >>"$LOG_FILE" 2>&1; then
    printf '\r\033[K  %s✔%s %s\n' "$C_GRN" "$C_OFF" "$msg"; return 0
  fi
  printf '\r\033[K  %s!%s %s %s(se omitió)%s\n' "$C_YLW" "$C_OFF" "$msg" "$C_DIM" "$C_OFF"; return 1
}

# ---------------------------------------------------------------- preguntas ---
have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ] && : </dev/tty 2>/dev/null; }

# ask VAR "Pregunta" "valor por defecto"  (si VAR ya viene del entorno, no pregunta)
ask() {
  local __v="$1" __q="$2" __d="${3:-}" __in=""
  if [ -n "${!__v:-}" ]; then return 0; fi
  if ! have_tty; then printf -v "$__v" '%s' "$__d"; return 0; fi
  read -r -p "  ${__q}${__d:+ [$__d]}: " __in </dev/tty || true
  printf -v "$__v" '%s' "${__in:-$__d}"
}

# ask_yn VAR "Pregunta" y|n
ask_yn() {
  local __v="$1" __q="$2" __d="${3:-n}" __in="" __hint
  if [ "$__d" = "y" ]; then __hint="Y/n"; else __hint="y/N"; fi
  if [ -n "${!__v:-}" ]; then
    case "${!__v}" in [yYsS]*) printf -v "$__v" 'y' ;; *) printf -v "$__v" 'n' ;; esac
    return 0
  fi
  if ! have_tty; then printf -v "$__v" '%s' "$__d"; return 0; fi
  while :; do
    read -r -p "  ${__q} [${__hint}]: " __in </dev/tty || true
    __in="${__in:-$__d}"
    case "$__in" in
      [yYsS]*) printf -v "$__v" 'y'; return 0 ;;
      [nN]*)   printf -v "$__v" 'n'; return 0 ;;
      *) warn "Responde y (sí) o n (no)." ;;
    esac
  done
}

# prompt_until VAR "Pregunta" "defecto" validador "mensaje de error"
prompt_until() {
  local var="$1" q="$2" def="$3" vf="$4" err="$5"
  while :; do
    ask "$var" "$q" "$def"
    if "$vf" "${!var}"; then return 0; fi
    warn "$err"
    if ! have_tty; then die "Valor inválido para ${var}: ${!var}"; fi
    unset "$var"
  done
}

valid_user()   { [[ "$1" =~ ^[a-zA-Z0-9_]{3,20}$ ]]; }
valid_port()   { [[ "$1" =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_domain() { [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; }
valid_email()  { [ -z "$1" ] || [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; }

port_busy() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
}

# ------------------------------------------------------------------ utilidades ---
public_ip() {
  local ip=""
  ip="$(curl -4 -fsS -m 6 https://api.ipify.org 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip="$(curl -4 -fsS -m 6 https://ifconfig.me 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  printf '%s' "$ip"
}

domain_ip() { getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1{print $1}' || true; }

users_exist() {
  local f="$INSTALL_DIR/data/users.json"
  [ -s "$f" ] || return 1
  node -e 'try{const u=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(Array.isArray(u)&&u.length?0:1)}catch(e){process.exit(1)}' "$f" 2>/dev/null
}

wait_http() { # wait_http URL segundos
  local url="$1" max="${2:-60}" i=0
  while [ "$i" -lt "$max" ]; do
    if curl -fsS -o /dev/null -m 3 "$url" 2>/dev/null; then return 0; fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

# ==============================================================================
#  PASOS
# ==============================================================================
banner() {
  say ""
  say "${C_BLD}${C_CYN}  ╔══════════════════════════════════════╗${C_OFF}"
  say "${C_BLD}${C_CYN}  ║        Kynex Panel · Instalador      ║${C_OFF}"
  say "${C_BLD}${C_CYN}  ╚══════════════════════════════════════╝${C_OFF}"
  say ""
}

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      info "Necesito permisos de administrador, reintentando con sudo..."
      exec sudo -E bash "$0" "$@"
    fi
    die "Ejecuta el instalador como root:  sudo bash $SELF_NAME"
  fi
  export HOME="${HOME:-/root}"
  [ "$HOME" = "/root" ] || export HOME=/root
}

init_log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  : >>"$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/kynex-install.log"
  chmod 600 "$LOG_FILE" 2>/dev/null || true
  printf '\n===== Instalación %s =====\n' "$(date '+%F %T')" >>"$LOG_FILE"
}

preflight() {
  step "Revisando el sistema"
  command -v apt-get >/dev/null 2>&1 || die "Este instalador es para Ubuntu/Debian (necesita apt-get)."
  . /etc/os-release 2>/dev/null || true
  ok "Sistema: ${PRETTY_NAME:-Linux}"

  case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) warn "Arquitectura $(uname -m) no probada; puede fallar la compilación de módulos." ;;
  esac

  local ram_mb free_mb
  ram_mb="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  [ "${ram_mb:-0}" -ge 900 ] || warn "Solo ${ram_mb} MB de RAM. Se recomienda 1 GB o más (te sugiero crear swap)."
  free_mb="$(df -Pm / | awk 'NR==2{print $4}')"
  [ "${free_mb:-0}" -ge 1500 ] || die "Poco espacio en disco (${free_mb} MB libres). Se necesitan al menos 1.5 GB."
  ok "Recursos: ${ram_mb} MB RAM · ${free_mb} MB libres"

  if ! command -v curl >/dev/null 2>&1; then
    soft "Instalando curl" bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates' \
      || die "No se pudo instalar curl."
  fi
  curl -fsS -m 12 -o /dev/null https://registry.npmjs.org/ 2>>"$LOG_FILE" \
    || die "No hay conexión a internet (no se pudo llegar a registry.npmjs.org). Revisa la red/DNS de la VPS."
  ok "Internet funcionando"

  [ -f "$SRC_DIR/server.js" ] && [ -f "$SRC_DIR/index.html" ] && [ -f "$SRC_DIR/package.json" ] \
    || die "No encuentro los archivos del panel junto al instalador.
     Pon $SELF_NAME en la MISMA carpeta que server.js, index.html y package.json, y vuelve a ejecutarlo."
  ok "Archivos del panel encontrados en $SRC_DIR"
}

detect_existing() {
  UPDATE_MODE="n"; HAS_USERS="n"; OLD_PORT=""
  if [ -f "$INSTALL_DIR/server.js" ]; then
    UPDATE_MODE="y"
    if command -v node >/dev/null 2>&1 && users_exist; then HAS_USERS="y"; fi
  fi
  return 0
}

ask_everything() {
  step "Configuración"

  if [ "$UPDATE_MODE" = "y" ]; then
    warn "Ya hay una instalación en $INSTALL_DIR."
    info "Se actualizarán los archivos del panel. Tus datos, usuarios y servidores NO se tocan."
    ask_yn KYNEX_UPDATE "¿Continuar con la actualización?" y
    [ "$KYNEX_UPDATE" = "y" ] || die "Cancelado por el usuario."
  fi

  if [ "$HAS_USERS" = "y" ]; then
    info "Ya existe un administrador: no se creará otro usuario."
  else
    say ""
    say "  ${C_BLD}Administrador principal${C_OFF}"
    prompt_until KYNEX_USER "Usuario (3-20 letras, números o _)" "" valid_user \
      "Usuario inválido: usa 3 a 20 caracteres (letras, números o guion bajo)."
    get_password
    prompt_until KYNEX_EMAIL "Correo (opcional, para recuperar la contraseña)" "" valid_email \
      "Correo inválido."
  fi

  say ""
  say "  ${C_BLD}SSL (HTTPS)${C_OFF}"
  info "Necesitas un dominio que ya apunte (registro A) a la IP de esta VPS. Sirve DuckDNS, No-IP, etc."
  ask_yn KYNEX_SSL "¿Activar SSL con Let's Encrypt (certbot)?" n
  SSL_ON="n"; DOMAIN=""; SSL_PORT="443"
  if [ "$KYNEX_SSL" = "y" ]; then
    prompt_until KYNEX_DOMAIN "Dominio (ej. panel.midominio.com)" "" valid_domain \
      "Dominio inválido. Escríbelo sin http:// ni barras, en minúsculas."
    DOMAIN="${KYNEX_DOMAIN,,}"
    prompt_until KYNEX_LE_EMAIL "Correo para avisos de Let's Encrypt (opcional)" "${KYNEX_EMAIL:-}" valid_email "Correo inválido."
    prompt_until KYNEX_SSL_PORT "Puerto HTTPS del panel" "443" valid_port "Puerto inválido (1-65535)."
    SSL_PORT="$KYNEX_SSL_PORT"
    SSL_ON="y"
  fi

  say ""
  say "  ${C_BLD}Puertos${C_OFF}"
  local defp="80"
  if [ "$SSL_ON" = "y" ]; then
    defp="3000"
    info "Con SSL entrarás por https://$DOMAIN (puerto 443, sin escribir puerto)."
    info "El puerto HTTP interno queda aparte porque el 80 lo necesita certbot para emitir/renovar."
  else
    info "Sin SSL el puerto 80 es el normal de internet: entrarás con http://IP o tu dominio, sin escribir puerto."
  fi
  prompt_until KYNEX_PORT "Puerto HTTP del panel" "$defp" valid_port "Puerto inválido (1-65535)."
  if [ "$SSL_ON" = "y" ] && [ "$KYNEX_PORT" = "80" ]; then
    warn "Con SSL el puerto HTTP no puede ser el 80 (certbot lo necesita): uso 3000."
    KYNEX_PORT=3000
  fi
  if [ "$SSL_ON" = "y" ] && [ "$SSL_PORT" = "$KYNEX_PORT" ]; then die "El puerto HTTP y el HTTPS no pueden ser el mismo."; fi
  if [ "$UPDATE_MODE" != "y" ] && port_busy "$KYNEX_PORT"; then
    die "El puerto $KYNEX_PORT ya está en uso por otro programa (nginx/apache?). Detenlo o usa otro:  KYNEX_PORT=3001 sudo -E bash $SELF_NAME"
  fi
  if [ "$SSL_ON" = "y" ] && [ "$UPDATE_MODE" != "y" ] && port_busy "$SSL_PORT"; then
    die "El puerto HTTPS $SSL_PORT ya está en uso por otro programa. Detenlo y ejecuta de nuevo."
  fi

  say ""
  say "  ${C_BLD}Opcionales${C_OFF}"
  ask_yn KYNEX_JAVA "¿Instalar Java ahora (para servidores de Minecraft Java)?" y
  ask_yn KYNEX_SMTP "¿Configurar correo SMTP (recuperación de contraseña por email)?" n
  SMTP_ON="n"
  if [ "$KYNEX_SMTP" = "y" ]; then
    ask KYNEX_SMTP_HOST "Servidor SMTP" "smtp.gmail.com"
    prompt_until KYNEX_SMTP_PORT "Puerto SMTP" "587" valid_port "Puerto inválido."
    ask KYNEX_SMTP_USER "Usuario/correo SMTP" ""
    if [ -z "${KYNEX_SMTP_PASS:-}" ] && have_tty; then
      read -rsp "  Contraseña SMTP (para Gmail usa una 'contraseña de aplicación'): " KYNEX_SMTP_PASS </dev/tty || true; echo
    fi
    ask KYNEX_SMTP_FROM "Remitente" "Kynex Panel <${KYNEX_SMTP_USER}>"
    if [ -n "${KYNEX_SMTP_HOST:-}" ] && [ -n "${KYNEX_SMTP_USER:-}" ] && [ -n "${KYNEX_SMTP_PASS:-}" ]; then
      SMTP_ON="y"
    else
      warn "Faltan datos SMTP: se omite la configuración de correo (puedes agregarla luego en ecosystem.config.js)."
    fi
  fi

  if [ "$SSL_ON" = "y" ]; then PUBLIC_PORT_SUFFIX=""; [ "$SSL_PORT" = "443" ] || PUBLIC_PORT_SUFFIX=":$SSL_PORT"; fi

  say ""
  say "  ${C_BLD}Resumen${C_OFF}"
  info "Carpeta de instalación : $INSTALL_DIR"
  [ "$HAS_USERS" = "y" ] || info "Administrador          : $KYNEX_USER"
  info "Puerto HTTP            : $KYNEX_PORT"
  if [ "$SSL_ON" = "y" ]; then info "SSL                    : sí · $DOMAIN (puerto $SSL_PORT)"; else info "SSL                    : no"; fi
  info "Java                   : $([ "$KYNEX_JAVA" = "y" ] && echo sí || echo no)"
  info "Correo SMTP            : $([ "$SMTP_ON" = "y" ] && echo "sí ($KYNEX_SMTP_HOST)" || echo no)"
  if have_tty && [ "${KYNEX_YES:-}" != "y" ]; then
    local go=""
    ask_yn go "¿Todo bien? ¿Instalar ahora?" y
    [ "$go" = "y" ] || die "Cancelado por el usuario."
  fi
}

get_password() {
  local p1="" p2=""
  while :; do
    if [ -n "${KYNEX_PASS:-}" ]; then
      p1="$KYNEX_PASS"; p2="$KYNEX_PASS"
    elif have_tty; then
      read -rsp "  Contraseña (mínimo ${MIN_PASS} caracteres): " p1 </dev/tty || true; echo
      read -rsp "  Repite la contraseña: " p2 </dev/tty || true; echo
    else
      die "No hay terminal para pedir la contraseña. Usa KYNEX_PASS='...' (ver ayuda arriba)."
    fi
    if [ "$p1" != "$p2" ]; then
      warn "Las contraseñas no coinciden."
    elif [ "${#p1}" -lt "$MIN_PASS" ]; then
      warn "Muy corta: usa al menos ${MIN_PASS} caracteres."
    else
      KYNEX_PASS="$p1"; return 0
    fi
    have_tty || die "Contraseña inválida."
    unset KYNEX_PASS
  done
}

# ------------------------------------------------------------- dependencias ---
apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold -o DPkg::Lock::Timeout=300 "$@"; }

install_system_packages() {
  step "Instalando paquetes del sistema"
  export DEBIAN_FRONTEND=noninteractive
  run "Actualizando lista de paquetes" apt-get update -qq -o DPkg::Lock::Timeout=300
  # iptables-persistent hace preguntas: se responden de antemano para que no se detenga
  echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>>"$LOG_FILE" || true
  echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>>"$LOG_FILE" || true
  run "Herramientas base (curl, git, zip, unzip, tar, openssl...)" \
    apt_install ca-certificates curl wget gnupg git zip unzip tar xz-utils openssl lsof procps iproute2 util-linux cron
  run "Compiladores (necesarios para la consola del panel)" \
    apt_install build-essential python3 python3-pip python3-dev make g++
  run "Firewall (iptables) para la protección anti-DDoS" \
    apt_install iptables iptables-persistent
  if [ "$SSL_ON" = "y" ]; then
    run "Certbot (certificados SSL)" apt_install certbot
  fi
}

node_major() { node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }

install_node() {
  step "Node.js"
  if command -v node >/dev/null 2>&1 && [ "$(node_major)" -ge "$MIN_NODE" ]; then
    ok "Node.js $(node -v) ya instalado"
  else
    info "Instalando Node.js ${NODE_MAJOR} LTS (repositorio oficial NodeSource)"
    run "Agregando repositorio de Node.js" bash -c '
      set -e
      install -d -m 0755 /etc/apt/keyrings
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
      chmod 644 /etc/apt/keyrings/nodesource.gpg
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_'"$NODE_MAJOR"'.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
      DEBIAN_FRONTEND=noninteractive apt-get update -qq -o DPkg::Lock::Timeout=300
    '
    run "Instalando Node.js ${NODE_MAJOR}" apt_install nodejs
    hash -r
    [ "$(node_major)" -ge "$MIN_NODE" ] || die "Node.js quedó en una versión menor a ${MIN_NODE} ($(node -v 2>/dev/null || echo ninguna))."
    ok "Node.js $(node -v) · npm $(npm -v)"
  fi
  command -v npm >/dev/null 2>&1 || run "Instalando npm" apt_install npm

  if command -v pm2 >/dev/null 2>&1; then
    ok "PM2 $(pm2 -v 2>/dev/null | tail -n1) ya instalado"
  else
    run "Instalando PM2" npm install -g pm2 --no-audit --no-fund
    hash -r
    command -v pm2 >/dev/null 2>&1 || die "PM2 no quedó en el PATH."
    ok "PM2 $(pm2 -v 2>/dev/null | tail -n1)"
  fi
}

install_java() {
  [ "$KYNEX_JAVA" = "y" ] || return 0
  step "Java"
  if command -v java >/dev/null 2>&1; then ok "Java ya instalado ($(java -version 2>&1 | head -n1))"; return 0; fi
  local v
  for v in 21 17 11; do
    if apt-cache show "openjdk-${v}-jre-headless" >/dev/null 2>&1; then
      if soft "Instalando OpenJDK ${v}" apt_install "openjdk-${v}-jre-headless"; then return 0; fi
    fi
  done
  warn "No se pudo instalar Java ahora. No pasa nada: el panel puede instalarlo desde su sección de Java."
}

# ------------------------------------------------------------ copiar el panel ---
deploy_files() {
  step "Instalando el panel"
  mkdir -p "$INSTALL_DIR"

  if [ -d "$INSTALL_DIR/data" ]; then
    local bk="/root/kynex-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    soft "Respaldo de tus datos en $bk" tar -czf "$bk" -C "$INSTALL_DIR" --exclude='data/backups' data \
      && chmod 600 "$bk" 2>/dev/null || true
  fi

  if [ "$(cd "$INSTALL_DIR" && pwd -P)" = "$SRC_DIR" ]; then
    ok "El instalador ya está dentro de $INSTALL_DIR (no hace falta copiar)"
  else
    run "Copiando archivos a $INSTALL_DIR" bash -c '
      set -e
      tar -C "$1" \
        --exclude="./'"$SELF_NAME"'" --exclude="./node_modules" --exclude="./data" --exclude="./servers" \
        --exclude="./backups" --exclude="./PMMP" --exclude="./.git" --exclude="./.pm2" \
        --exclude="./ecosystem.config.js" --exclude="./*.log" --exclude="./*.tar.gz" -cf - . \
        | tar -C "$2" -xf -
    ' _ "$SRC_DIR" "$INSTALL_DIR"
  fi
  mkdir -p "$INSTALL_DIR/data"
  chmod 700 "$INSTALL_DIR/data"

  # los uploads de Windows a veces traen finales de línea CRLF en los .js: se normalizan
  find "$INSTALL_DIR" -maxdepth 1 -name '*.js' -exec sed -i 's/\r$//' {} + 2>>"$LOG_FILE" || true

  ( cd "$INSTALL_DIR" && run "Instalando dependencias de Node (puede tardar unos minutos)" \
      npm install --omit=dev --legacy-peer-deps --no-audit --no-fund --loglevel=error )

  ( cd "$INSTALL_DIR" && run "Comprobando que los módulos cargan bien" node -e '
    const need=["express","express-rate-limit","cookie-parser","multer","ws","node-cron","geoip-lite","node-pty","nodemailer"];
    const bad=[];for(const m of need){try{require(m)}catch(e){bad.push(m+": "+e.message.split("\n")[0])}}
    if(bad.length){console.error(bad.join("\n"));process.exit(1)}' ) || {
      warn "Algún módulo no cargó; intento recompilar node-pty..."
      ( cd "$INSTALL_DIR" && run "Recompilando node-pty" npm rebuild node-pty )
      ( cd "$INSTALL_DIR" && run "Verificando de nuevo" node -e 'require("node-pty");require("express");require("geoip-lite")' )
    }
  ( cd "$INSTALL_DIR" && node --check server.js >>"$LOG_FILE" 2>&1 ) || die "server.js tiene un error de sintaxis (revisa el archivo que copiaste)."
  ok "Panel listo en $INSTALL_DIR"
}

# ---------------------------------------------------------------- firewall ---
open_firewall() {
  step "Firewall"
  local did=0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    soft "ufw: abriendo puerto del panel ($KYNEX_PORT)" ufw allow "${KYNEX_PORT}/tcp" || true
    if [ "$SSL_ON" = "y" ]; then
      soft "ufw: abriendo 80 y $SSL_PORT (SSL)" bash -c "ufw allow 80/tcp && ufw allow ${SSL_PORT}/tcp" || true
    fi
    soft "ufw: abriendo puertos de juegos ($GAME_PORT_MIN-$GAME_PORT_MAX)" bash -c "ufw allow ${GAME_PORT_MIN}:${GAME_PORT_MAX}/tcp && ufw allow ${GAME_PORT_MIN}:${GAME_PORT_MAX}/udp" || true
    did=1
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    soft "firewalld: abriendo puertos" bash -c "firewall-cmd --permanent --add-port=${KYNEX_PORT}/tcp --add-port=80/tcp --add-port=${SSL_PORT}/tcp --add-port=${GAME_PORT_MIN}-${GAME_PORT_MAX}/tcp --add-port=${GAME_PORT_MIN}-${GAME_PORT_MAX}/udp && firewall-cmd --reload" || true
    did=1
  fi
  if [ "$did" = "0" ]; then
    info "No hay ufw/firewalld activo, no se tocó nada."
  fi
  info "Si tu proveedor (Oracle, AWS, Google...) tiene firewall propio, abre allí: ${KYNEX_PORT}$([ "$SSL_ON" = "y" ] && echo ", 80, ${SSL_PORT}")  y  ${GAME_PORT_MIN}-${GAME_PORT_MAX} (TCP/UDP)."
}

# --------------------------------------------------------------------- SSL ---
setup_ssl() {
  SSL_OK="n"
  [ "$SSL_ON" = "y" ] || return 0
  step "Certificado SSL (Let's Encrypt)"

  local my_ip dom_ip
  my_ip="$(public_ip)"; dom_ip="$(domain_ip "$DOMAIN")"
  if [ -z "$dom_ip" ]; then
    warn "El dominio $DOMAIN todavía no resuelve a ninguna IP."
  elif [ -n "$my_ip" ] && [ "$dom_ip" != "$my_ip" ]; then
    warn "$DOMAIN apunta a $dom_ip pero esta VPS es $my_ip."
  else
    ok "$DOMAIN apunta a esta VPS ($my_ip)"
  fi
  if [ -z "$dom_ip" ] || { [ -n "$my_ip" ] && [ "$dom_ip" != "$my_ip" ]; }; then
    local go="n"
    if have_tty; then ask_yn go "Si el DNS no apunta aquí, Let's Encrypt va a fallar. ¿Intentar de todos modos?" n; fi
    if [ "$go" != "y" ]; then
      warn "Se omite el SSL. Arregla el DNS y ejecuta de nuevo el instalador para activarlo."
      return 0
    fi
  fi

  if port_busy 80; then
    warn "El puerto 80 está ocupado por otro programa (nginx/apache?). Certbot lo necesita libre un momento."
    warn "Detén ese servicio y ejecuta de nuevo el instalador. Se omite el SSL por ahora."
    return 0
  fi

  local email_args=(--register-unsafely-without-email)
  [ -n "${KYNEX_LE_EMAIL:-}" ] && email_args=(--email "$KYNEX_LE_EMAIL")

  if ! soft "Pidiendo el certificado para $DOMAIN" \
      certbot certonly --standalone --non-interactive --agree-tos --preferred-challenges http \
      "${email_args[@]}" -d "$DOMAIN"; then
    warn "Let's Encrypt no pudo emitir el certificado (revisa el DNS, que el puerto 80 sea accesible desde internet y el firewall del proveedor)."
    info "Detalle: tail -n 30 /var/log/letsencrypt/letsencrypt.log"
    warn "El panel se instalará sin SSL. Puedes repetirlo luego ejecutando de nuevo el instalador."
    return 0
  fi

  local live="/etc/letsencrypt/live/$DOMAIN"
  [ -f "$live/fullchain.pem" ] && [ -f "$live/privkey.pem" ] || { warn "No encuentro los archivos del certificado en $live; se omite el SSL."; return 0; }
  mkdir -p "$INSTALL_DIR/data/ssl"; chmod 700 "$INSTALL_DIR/data/ssl"
  cp -L "$live/privkey.pem"   "$INSTALL_DIR/data/ssl/key.pem"
  cp -L "$live/fullchain.pem" "$INSTALL_DIR/data/ssl/cert.pem"
  chmod 600 "$INSTALL_DIR/data/ssl/key.pem"; chmod 644 "$INSTALL_DIR/data/ssl/cert.pem"
  ok "Certificado copiado al panel (data/ssl)"

  # Renovación automática: cuando certbot renueve, copia el certificado nuevo y reinicia el panel
  mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  local pm2bin; pm2bin="$(command -v pm2)"
  cat >/etc/letsencrypt/renewal-hooks/deploy/kynex-panel.sh <<EOF
#!/bin/sh
# Generado por el instalador de Kynex Panel
LIVE="/etc/letsencrypt/live/$DOMAIN"
DEST="$INSTALL_DIR/data/ssl"
cp -L "\$LIVE/privkey.pem"   "\$DEST/key.pem"  &&
cp -L "\$LIVE/fullchain.pem" "\$DEST/cert.pem" &&
chmod 600 "\$DEST/key.pem" && chmod 644 "\$DEST/cert.pem" &&
HOME=/root PM2_HOME=/root/.pm2 PATH="\$PATH:$(dirname "$pm2bin")" "$pm2bin" restart $APP_NAME >/dev/null 2>&1
exit 0
EOF
  chmod 755 /etc/letsencrypt/renewal-hooks/deploy/kynex-panel.sh
  command -v systemctl >/dev/null 2>&1 && soft "Activando la renovación automática" systemctl enable --now certbot.timer || true
  soft "Probando que la renovación funcionará" certbot renew --dry-run --cert-name "$DOMAIN" || \
    warn "La prueba de renovación falló. Revisa que el puerto 80 esté libre y accesible cuando toque renovar."
  SSL_OK="y"
}

# --------------------------------------------------------------- PM2 + panel ---
write_ecosystem() {
  local pub
  if [ "$SSL_OK" = "y" ]; then
    pub="https://$DOMAIN"; [ "$SSL_PORT" = "443" ] || pub="$pub:$SSL_PORT"
  else
    local ip; ip="$(public_ip)"; pub="http://${ip:-localhost}"; [ "$KYNEX_PORT" = "80" ] || pub="$pub:$KYNEX_PORT"
  fi
  PUBLIC_URL="$pub"
  # se escribe con Node para que cualquier carácter raro en las contraseñas quede bien escapado
  E_PORT="$KYNEX_PORT" E_SSLPORT="$SSL_PORT" E_URL="$pub" E_SMTP="$SMTP_ON" \
  E_HOST="${KYNEX_SMTP_HOST:-}" E_SPORT="${KYNEX_SMTP_PORT:-587}" E_USER="${KYNEX_SMTP_USER:-}" \
  E_PASS="${KYNEX_SMTP_PASS:-}" E_FROM="${KYNEX_SMTP_FROM:-}" E_FILE="$INSTALL_DIR/ecosystem.config.js" E_NAME="$APP_NAME" \
  node -e '
    const e=process.env,fs=require("fs");
    const env={NODE_ENV:"production",PANEL_PORT:e.E_PORT,PANEL_SSL_PORT:e.E_SSLPORT,PANEL_PUBLIC_URL:e.E_URL};
    if(e.E_SMTP==="y"){env.SMTP_HOST=e.E_HOST;env.SMTP_PORT=e.E_SPORT;env.SMTP_USER=e.E_USER;env.SMTP_PASS=e.E_PASS;
      env.SMTP_FROM=e.E_FROM||e.E_USER;if(e.E_SPORT==="465")env.SMTP_SECURE="true";}
    const cfg={apps:[{name:e.E_NAME,script:"server.js",cwd:"__DIRNAME__",autorestart:true,
      max_restarts:50,min_uptime:"10s",restart_delay:3000,kill_timeout:15000,env}]};
    let out="// Generado por install.sh · contiene credenciales: no lo compartas\nmodule.exports = "+JSON.stringify(cfg,null,2)+";\n";
    out=out.replace("\"__DIRNAME__\"","__dirname");
    fs.writeFileSync(e.E_FILE,out,{mode:0o600});
  ' 2>>"$LOG_FILE" || die "No se pudo escribir ecosystem.config.js"
  chmod 600 "$INSTALL_DIR/ecosystem.config.js"
  ok "Configuración de PM2 escrita (ecosystem.config.js)"
}

start_panel() {
  step "Arrancando el panel con PM2"
  export PM2_HOME="${PM2_HOME:-/root/.pm2}"
  write_ecosystem
  ( cd "$INSTALL_DIR" && run "Iniciando $APP_NAME" pm2 startOrRestart ecosystem.config.js --update-env )
  soft "Guardando la lista de procesos de PM2" pm2 save --force || true
  soft "Rotación de logs (para que no llenen el disco)" bash -c 'pm2 install pm2-logrotate && pm2 set pm2-logrotate:max_size 20M && pm2 set pm2-logrotate:retain 7 && pm2 set pm2-logrotate:compress true' || true

  if [ -d /run/systemd/system ]; then
    local pm2bin; pm2bin="$(command -v pm2)"
    soft "Configurando arranque automático al reiniciar la VPS" \
      env PATH="$PATH:$(dirname "$pm2bin")" "$pm2bin" startup systemd -u root --hp /root || true
    if ! systemctl is-enabled pm2-root >/dev/null 2>&1; then
      info "pm2 startup no dejó el servicio; lo creo a mano."
      cat >/etc/systemd/system/pm2-root.service <<EOF
[Unit]
Description=PM2 process manager
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=root
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PATH=$PATH:$(dirname "$pm2bin")
Environment=PM2_HOME=/root/.pm2
PIDFile=/root/.pm2/pm2.pid
Restart=on-failure
ExecStart=$pm2bin resurrect
ExecReload=$pm2bin reload all
ExecStop=$pm2bin kill

[Install]
WantedBy=multi-user.target
EOF
      run "Activando el servicio pm2-root" bash -c 'systemctl daemon-reload && systemctl enable pm2-root'
    fi
    soft "Guardando de nuevo la lista de PM2" pm2 save --force || true
    systemctl is-enabled pm2-root >/dev/null 2>&1 && ok "El panel arrancará solo cuando se reinicie la VPS" \
      || warn "No pude confirmar el arranque automático. Prueba luego:  pm2 startup && pm2 save"
  else
    warn "Este sistema no usa systemd: no se configuró el arranque automático. Ejecuta 'pm2 startup' y sigue sus instrucciones."
  fi

  printf '  %s…%s Esperando a que el panel responda' "$C_DIM" "$C_OFF"
  if wait_http "http://127.0.0.1:${KYNEX_PORT}/" 90; then
    printf '\r\033[K  %s✔%s El panel está en línea\n' "$C_GRN" "$C_OFF"
  else
    printf '\r\033[K  %s✘%s El panel no respondió\n' "$C_RED" "$C_OFF"
    pm2 logs "$APP_NAME" --lines 40 --nostream 2>&1 | tail -n 40 | tee -a "$LOG_FILE" >&2 || true
    die "El panel no arrancó. Mira los logs de arriba (o: pm2 logs $APP_NAME)."
  fi
  if [ "$SSL_OK" = "y" ]; then
    if wait_http "https://127.0.0.1:${SSL_PORT}/" 20 2>/dev/null || curl -fsSk -o /dev/null -m 5 "https://127.0.0.1:${SSL_PORT}/" 2>/dev/null; then
      ok "HTTPS funcionando en el puerto $SSL_PORT"
    else
      warn "El puerto HTTPS $SSL_PORT no respondió todavía. Mira:  pm2 logs $APP_NAME"
    fi
  fi
}

# ------------------------------------------------------------- administrador ---
create_admin() {
  ADMIN_CREATED="n"
  [ "$HAS_USERS" = "y" ] && return 0
  step "Creando el administrador principal"
  if users_exist; then info "Ya hay usuarios registrados: no se crea otro."; return 0; fi
  local resp
  resp="$(KU="$KYNEX_USER" KP="$KYNEX_PASS" KE="${KYNEX_EMAIL:-}" node -e '
      const e=process.env;const b={username:e.KU,password:e.KP,confirmPassword:e.KP};
      if(e.KE)b.email=e.KE;process.stdout.write(JSON.stringify(b));' \
    | curl -sS -m 30 -X POST "http://127.0.0.1:${KYNEX_PORT}/api/register" \
        -H 'Content-Type: application/json' --data-binary @- 2>>"$LOG_FILE" || true)"
  if printf '%s' "$resp" | grep -q '"success":true'; then
    ok "Administrador «$KYNEX_USER» creado"
    ADMIN_CREATED="y"
  else
    printf '%s\n' "$resp" >>"$LOG_FILE"
    warn "No se pudo crear el administrador automáticamente: ${resp:-sin respuesta}"
    warn "No pasa nada: abre el panel y registra tu usuario (el primero que se registre será el administrador)."
  fi
}

# ------------------------------------------------------------------- final ---
final_summary() {
  local url="$PUBLIC_URL"
  say ""
  say "${C_BLD}${C_GRN}  ══════════════ Instalación terminada ══════════════${C_OFF}"
  say ""
  say "  ${C_BLD}Panel:${C_OFF}   $url"
  if [ "$SSL_OK" != "y" ]; then
    say "           (también en http://localhost:${KYNEX_PORT} dentro de la VPS)"
  fi
  if [ "${ADMIN_CREATED:-n}" = "y" ]; then
    say "  ${C_BLD}Usuario:${C_OFF} $KYNEX_USER  ${C_DIM}(administrador principal)${C_OFF}"
  elif [ "$HAS_USERS" = "y" ]; then
    say "  ${C_BLD}Usuario:${C_OFF} el administrador que ya tenías"
  fi
  say ""
  say "  ${C_BLD}Comandos útiles${C_OFF}"
  say "    pm2 list                   ver si el panel está corriendo"
  say "    pm2 logs $APP_NAME     ver los logs en vivo"
  say "    pm2 restart $APP_NAME  reiniciar el panel"
  say "    pm2 stop $APP_NAME     apagarlo   ·   pm2 start $APP_NAME   prenderlo"
  say ""
  say "  ${C_BLD}Rutas${C_OFF}"
  say "    Panel y datos:  $INSTALL_DIR"
  say "    Configuración:  $INSTALL_DIR/ecosystem.config.js  ${C_DIM}(PM2 y correo; luego: pm2 restart $APP_NAME --update-env)${C_OFF}"
  say "    Registro de esta instalación: $LOG_FILE"
  say ""
  if [ "$SSL_OK" = "y" ]; then
    say "  ${C_BLD}SSL:${C_OFF} el certificado se renueva solo (certbot) y reinicia el panel al hacerlo."
    say "       ${C_DIM}El puerto HTTP ${KYNEX_PORT} sigue abierto; usa siempre https://$DOMAIN$([ "$SSL_PORT" = "443" ] || echo ":$SSL_PORT").${C_OFF}"
    say ""
  fi
  say "  ${C_BLD}Para actualizar el panel después:${C_OFF} pon los archivos nuevos junto a $SELF_NAME y ejecútalo otra vez."
  say "  ${C_DIM}Tus datos, usuarios y servidores se conservan.${C_OFF}"
  say ""
}

main() {
  case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac
  require_root "$@"
  init_log
  banner
  preflight
  detect_existing
  ask_everything
  install_system_packages
  install_node
  install_java
  deploy_files
  open_firewall
  setup_ssl
  start_panel
  create_admin
  final_summary
}

# Permite cargar el archivo solo para probar funciones: KYNEX_SOURCE_ONLY=1 source install.sh
if [ "${KYNEX_SOURCE_ONLY:-}" != "1" ]; then
  main "$@"
fi
