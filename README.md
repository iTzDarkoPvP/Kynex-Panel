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

Tus datos, usuarios y servidores se conservan.

---

<div align="center">Hecho con ❤️ por <b>DarkoDevv</b></div>
