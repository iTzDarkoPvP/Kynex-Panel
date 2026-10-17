#!/usr/bin/env bash
# ==============================================================================
#  Kynex Panel · Configurar correo (recuperación de contraseña)
#
#  Uso:   sudo bash recovery.sh
#
#  Sirve para configurar (o cambiar, o quitar) el correo SMTP del panel cuando
#  en install.sh respondiste "n". No reinstala nada: solo edita
#  ecosystem.config.js y reinicia el panel con PM2.
#
#  Modo automático (sin preguntas):
#    KYNEX_SMTP_HOST=smtp.gmail.com KYNEX_SMTP_PORT=587 KYNEX_SMTP_USER=tu@gmail.com \
#    KYNEX_SMTP_PASS='clave-de-aplicacion' sudo -E bash recovery.sh
#  Para quitar el correo:  KYNEX_SMTP_REMOVE=y sudo -E bash recovery.sh
#  Variables: KYNEX_SMTP_HOST/PORT/USER/PASS/FROM  INSTALL_DIR
# ==============================================================================
set -Eeuo pipefail

APP_NAME="kynex-panel"
INSTALL_DIR="${INSTALL_DIR:-/opt/kynex-panel}"
ECO="$INSTALL_DIR/ecosystem.config.js"

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
die()  { printf '\n  %s✘ %s%s\n\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }

have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ] && : </dev/tty 2>/dev/null; }

ask() { # ask VAR "Pregunta" "defecto"
  local __v="$1" __q="$2" __d="${3:-}" __in=""
  if [ -n "${!__v:-}" ]; then return 0; fi
  if ! have_tty; then printf -v "$__v" '%s' "$__d"; return 0; fi
  read -r -p "  ${__q}${__d:+ [$__d]}: " __in </dev/tty || true
  printf -v "$__v" '%s' "${__in:-$__d}"
}

ask_yn() { # ask_yn VAR "Pregunta" y|n
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

valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# ------------------------------------------------------------------ checks ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  fi
  die "Ejecuta como root:  sudo bash recovery.sh"
fi
export HOME=/root
export PM2_HOME="${PM2_HOME:-/root/.pm2}"

say ""
say "${C_BLD}${C_CYN}  ╔══════════════════════════════════════╗${C_OFF}"
say "${C_BLD}${C_CYN}  ║  Kynex Panel · Correo de recuperación ║${C_OFF}"
say "${C_BLD}${C_CYN}  ╚══════════════════════════════════════╝${C_OFF}"
say ""

command -v node >/dev/null 2>&1 || die "No encuentro Node.js. ¿Ya ejecutaste install.sh?"
command -v pm2  >/dev/null 2>&1 || die "No encuentro PM2. ¿Ya ejecutaste install.sh?"
[ -f "$ECO" ] || die "No existe $ECO. Ejecuta primero install.sh (o usa INSTALL_DIR=/ruta)."

# ------------------------------------------------------------ quitar correo ---
KYNEX_SMTP_REMOVE="${KYNEX_SMTP_REMOVE:-}"
if [ -z "$KYNEX_SMTP_REMOVE" ] && have_tty && [ -z "${KYNEX_SMTP_HOST:-}" ]; then
  if node -e 'const c=require(process.argv[1]);process.exit(c.apps[0].env.SMTP_HOST?0:1)' "$ECO" 2>/dev/null; then
    warn "Ya hay un correo configurado."
    ask_yn KYNEX_SMTP_REMOVE "¿Quieres QUITARLO en vez de cambiarlo?" n
  fi
fi

write_eco() { # write_eco "modo" (set|remove)
  E_MODE="$1" E_FILE="$ECO" \
  E_HOST="${KYNEX_SMTP_HOST:-}" E_PORT="${KYNEX_SMTP_PORT:-587}" E_USER="${KYNEX_SMTP_USER:-}" \
  E_PASS="${KYNEX_SMTP_PASS:-}" E_FROM="${KYNEX_SMTP_FROM:-}" \
  node -e '
    const fs=require("fs"),e=process.env;
    const cfg=require(e.E_FILE);
    const app=cfg.apps[0];
    const cwd=app.cwd;
    for(const k of ["SMTP_HOST","SMTP_PORT","SMTP_USER","SMTP_PASS","SMTP_FROM","SMTP_SECURE"])delete app.env[k];
    if(e.E_MODE==="set"){
      app.env.SMTP_HOST=e.E_HOST;app.env.SMTP_PORT=e.E_PORT;app.env.SMTP_USER=e.E_USER;app.env.SMTP_PASS=e.E_PASS;
      app.env.SMTP_FROM=e.E_FROM||e.E_USER;
      if(e.E_PORT==="465")app.env.SMTP_SECURE="true";
    }
    let out="// Generado por install.sh · contiene credenciales: no lo compartas\nmodule.exports = "+JSON.stringify(cfg,null,2)+";\n";
    out=out.replace(JSON.stringify(cwd),"__dirname");
    fs.writeFileSync(e.E_FILE+".tmp",out,{mode:0o600});
    fs.renameSync(e.E_FILE+".tmp",e.E_FILE);
  ' || die "No se pudo escribir ecosystem.config.js"
  chmod 600 "$ECO"
}

restart_panel() {
  printf '  %s…%s Reiniciando el panel' "$C_DIM" "$C_OFF"
  if ( cd "$INSTALL_DIR" && pm2 startOrRestart ecosystem.config.js --update-env >/dev/null 2>&1 ); then
    pm2 save --force >/dev/null 2>&1 || true
    printf '\r\033[K  %s✔%s Panel reiniciado\n' "$C_GRN" "$C_OFF"
  else
    printf '\r\033[K  %s✘%s No se pudo reiniciar\n' "$C_RED" "$C_OFF"
    die "Reinicia a mano:  pm2 restart $APP_NAME --update-env"
  fi
}

if [ "$KYNEX_SMTP_REMOVE" = "y" ]; then
  write_eco remove
  ok "Correo SMTP eliminado de la configuración"
  restart_panel
  say ""
  exit 0
fi

# ------------------------------------------------------------------ datos ---
say "  ${C_BLD}Datos del correo (SMTP)${C_OFF}"
info "Gmail: usa smtp.gmail.com, puerto 587 y una 'contraseña de aplicación' (no tu clave normal)."
say ""
ask KYNEX_SMTP_HOST "Servidor SMTP" "smtp.gmail.com"
while :; do
  ask KYNEX_SMTP_PORT "Puerto SMTP" "587"
  valid_port "$KYNEX_SMTP_PORT" && break
  warn "Puerto inválido (1-65535)."
  have_tty || die "Puerto inválido: $KYNEX_SMTP_PORT"
  unset KYNEX_SMTP_PORT
done
ask KYNEX_SMTP_USER "Usuario/correo SMTP" ""
if [ -z "${KYNEX_SMTP_PASS:-}" ] && have_tty; then
  read -rsp "  Contraseña SMTP: " KYNEX_SMTP_PASS </dev/tty || true; echo
fi
ask KYNEX_SMTP_FROM "Remitente" "Kynex Panel <${KYNEX_SMTP_USER}>"

if [ -z "${KYNEX_SMTP_HOST:-}" ] || [ -z "${KYNEX_SMTP_USER:-}" ] || [ -z "${KYNEX_SMTP_PASS:-}" ]; then
  die "Faltan datos: servidor, usuario y contraseña son obligatorios."
fi

# ------------------------------------------------------- probar conexión ---
printf '  %s…%s Probando la conexión con el servidor de correo' "$C_DIM" "$C_OFF"
TEST_ERR="$(cd "$INSTALL_DIR" && E_HOST="$KYNEX_SMTP_HOST" E_PORT="$KYNEX_SMTP_PORT" E_USER="$KYNEX_SMTP_USER" E_PASS="$KYNEX_SMTP_PASS" node -e '
  const e=process.env;let nm;try{nm=require("nodemailer");}catch(x){console.log("nodemailer no está instalado (ejecuta install.sh de nuevo)");process.exit(2);}
  const t=nm.createTransport({host:e.E_HOST,port:parseInt(e.E_PORT,10),secure:e.E_PORT==="465",auth:{user:e.E_USER,pass:e.E_PASS},connectionTimeout:12000,greetingTimeout:12000,socketTimeout:15000});
  t.verify().then(()=>process.exit(0)).catch(x=>{console.log(String(x.message||x).split("\n")[0]);process.exit(1);});
' 2>&1 || true)"
if [ -z "$TEST_ERR" ]; then
  printf '\r\033[K  %s✔%s Conexión correcta, el correo funciona\n' "$C_GRN" "$C_OFF"
else
  printf '\r\033[K  %s!%s No se pudo conectar: %s\n' "$C_YLW" "$C_OFF" "$TEST_ERR"
  go="n"
  if have_tty; then ask_yn go "¿Guardar la configuración de todos modos?" n; fi
  [ "$go" = "y" ] || die "Cancelado. Revisa servidor, puerto, usuario y contraseña, y vuelve a intentarlo."
fi

# --------------------------------------------------------------- guardar ---
write_eco set
ok "Configuración guardada en ecosystem.config.js"
restart_panel

say ""
say "  ${C_BLD}${C_GRN}Listo.${C_OFF} Ya puedes usar «¿Olvidaste tu contraseña?» en el login del panel."
info "Recuerda: cada usuario debe tener un correo guardado en Mi Cuenta para recibir el enlace."
say ""
