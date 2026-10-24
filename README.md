<div align="center">

# 🔥 KYNEX PANEL

**Panel para crear y administrar servidores de Minecraft, bots y más, todo desde la web.**

![Node.js](https://img.shields.io/badge/Node.js-18%2B-68a063?logo=node.js&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-e95420?logo=ubuntu&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-11%2B-a81d33?logo=debian&logoColor=white)

</div>

## ✨ Qué incluye

- 🖥️ Servidores Bedrock y Java (PocketMine, Nukkit, Paper, Spigot, Vanilla) y bots de Python/Node.js
- 💻 Consola en vivo, editor de archivos, backups y tareas programadas
- 🧩 Tienda de plugins, 🛡️ anti-DDoS, usuarios con permisos y temas personalizables
- 🔨 **Baneos completos**: por cuenta, IP, dispositivo y red, con pantalla de "Has sido baneado" (IP, país, ciudad, navegador...)
- 🗜️ Descomprime `.zip`, `.rar`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst` desde el gestor de archivos
- 🌍 Español, English y Português

## 🚀 Instalación

Necesitas un VPS con **Ubuntu 20.04+** o **Debian 11+** y acceso root.

```bash
apt update && apt install -y git
git clone https://github.com/iTzDarkoPvP/Kynex-Panel.git
cd Kynex-Panel
sudo bash install.sh
```

El instalador te pide tu usuario y contraseña de administrador, y opcionalmente SSL, puerto y Java. Al terminar, abre `http://IP_DE_TU_VPS` en el navegador.

También deja instaladas las herramientas de compresión: `zip`, `unzip`, `tar`, `gzip`, `bzip2`, `xz`, `zstd`, `7z`, `unrar`/`unar` y `bsdtar`. Si alguna no existe en tu sistema (por ejemplo `rar` en Debian) se omite sin detener la instalación.

## 🔨 Baneos

Desde **Administradores** puedes banear a cualquier usuario que no sea admin.

- **Banear:** pulsa **Banear**, escribe un motivo (opcional) y listo. Su sesión se cierra al instante.
- **Desbanear:** pulsa **Desbanear** en su tarjeta, o en la lista **Baneados** que aparece debajo.
- **Banear una IP a mano:** botón **Banear IP** en esa misma lista.

**Qué se bloquea:** la cuenta, todas las IPs desde las que entró, su navegador/dispositivo (cookie propia del panel) y la misma red con el mismo navegador. Con eso no puede iniciar sesión, **registrarse de nuevo** ni entrar a cuentas ajenas.

**Qué ve la persona baneada:** una pantalla grande de **"Has sido baneado"** con el motivo y su información: IP, país, región, ciudad, zona horaria, proveedor, navegador, sistema, idioma, ID de dispositivo, ID de baneo y fecha. Tiene botón para copiar la información y reintentar. Si la desbaneas, la pantalla se quita sola.

**Importante:**

- Los **administradores nunca se bloquean** por IP/dispositivo, y las IPs locales o privadas jamás se banean.
- Si baneas a alguien que comparte IP (misma casa, wifi pública o red móvil), esas personas también quedan bloqueadas. Revisa las IPs en la lista y quita el baneo si hace falta.
- Ningún baneo es infalible: alguien con otra IP (VPN), otro navegador y sin cookies puede intentar volver. Por eso se combinan cuenta + IP + dispositivo + red.
- Los baneos se guardan en `data/bans.json` y se conservan al actualizar. Borrar un usuario **no** quita su baneo.

**Emergencia (quitar todos los baneos desde la consola):**

```bash
cd /opt/kynex-panel && pm2 stop kynex-panel
node -e "const f=require('fs');f.writeFileSync('data/bans.json','[]');const u=JSON.parse(f.readFileSync('data/users.json','utf8'));u.forEach(x=>{delete x.banned;delete x.banReason;delete x.bannedAt});f.writeFileSync('data/users.json',JSON.stringify(u,null,2))"
pm2 start kynex-panel
```

## 🔒 SSL (opcional)

Apunta un dominio a la IP del VPS y responde **sí** a SSL en el instalador. El certificado se renueva solo.

## 🔥 Puertos a abrir

`80` (panel), `443` (si usas SSL) y `19132-26000` TCP/UDP (servidores).

## 🛠️ Comandos útiles

```bash
pm2 list                  # ver estado
pm2 logs kynex-panel      # ver logs
pm2 restart kynex-panel   # reiniciar
```

## 🔄 Actualizar

```bash
cd Kynex-Panel && git pull && sudo bash install.sh
```

Tus datos, usuarios, servidores y baneos se conservan.

---

<div align="center">Hecho con ❤️ por <b>DarkoDevv</b></div>
