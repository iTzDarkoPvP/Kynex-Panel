let nodemailer = null;
try { nodemailer = require('nodemailer'); } catch (e) {}

const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = parseInt(process.env.SMTP_PORT || '587', 10);
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_SECURE = process.env.SMTP_SECURE === 'true';
const SMTP_FROM = process.env.SMTP_FROM || SMTP_USER;
const PANEL_PUBLIC_URL = process.env.PANEL_PUBLIC_URL || '';

let transport = null;
let warnedOnce = false;

function isConfigured() {
  return !!(nodemailer && SMTP_HOST && SMTP_USER && SMTP_PASS);
}

function getTransport(log) {
  if (transport) return transport;
  if (!isConfigured()) return null;
  try {
    transport = nodemailer.createTransport({
      host: SMTP_HOST,
      port: SMTP_PORT,
      secure: SMTP_SECURE,
      auth: { user: SMTP_USER, pass: SMTP_PASS }
    });
  } catch (e) {
    if (log) log.err('MAIL', 'No se pudo crear el transporte SMTP: ' + e.message);
    return null;
  }
  return transport;
}

function escHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

function buildPanelLink(req, extraQuery) {
  const base = (PANEL_PUBLIC_URL || (req ? (req.protocol + '://' + req.get('host')) : '')).replace(/\/+$/, '');
  return base + '/' + (extraQuery || '');
}

const RESET_I18N = {
  es: {
    subject: 'Restablece tu contraseña - Kynex Panel',
    preheader: 'Enlace para restablecer tu contraseña. Expira en 30 minutos.',
    title: 'Kynex Panel',
    eyebrow: 'RECUPERACIÓN DE CONTRASEÑA',
    hello: 'Hola',
    intro: 'Recibimos una solicitud para restablecer la contraseña de tu cuenta. Haz clic en el botón de abajo para elegir una nueva.',
    button: 'Restablecer contraseña',
    expiry: 'Este enlace expira en 30 minutos por seguridad.',
    altText: 'Si el botón no funciona, copia y pega este enlace en tu navegador:',
    ignoreTitle: '¿No fuiste tú?',
    ignore: 'Si no solicitaste este cambio, puedes ignorar este correo con seguridad; tu contraseña no cambiará.',
    footer: 'Este es un correo automático, por favor no respondas a este mensaje.'
  },
  en: {
    subject: 'Reset your password - Kynex Panel',
    preheader: 'Link to reset your password. Expires in 30 minutes.',
    title: 'Kynex Panel',
    eyebrow: 'PASSWORD RECOVERY',
    hello: 'Hi',
    intro: 'We received a request to reset your account password. Click the button below to choose a new one.',
    button: 'Reset password',
    expiry: 'For your security, this link expires in 30 minutes.',
    altText: "If the button doesn't work, copy and paste this link into your browser:",
    ignoreTitle: "Wasn't you?",
    ignore: "If you didn't request this, you can safely ignore this email; your password will not change.",
    footer: 'This is an automated email, please do not reply to this message.'
  },
  pt: {
    subject: 'Redefina sua senha - Kynex Panel',
    preheader: 'Link para redefinir sua senha. Expira em 30 minutos.',
    title: 'Kynex Panel',
    eyebrow: 'RECUPERAÇÃO DE SENHA',
    hello: 'Olá',
    intro: 'Recebemos uma solicitação para redefinir a senha da sua conta. Clique no botão abaixo para escolher uma nova.',
    button: 'Redefinir senha',
    expiry: 'Por segurança, este link expira em 30 minutos.',
    altText: 'Se o botão não funcionar, copie e cole este link no seu navegador:',
    ignoreTitle: 'Não foi você?',
    ignore: 'Se não foi você quem solicitou isso, pode ignorar este e-mail com segurança; sua senha não será alterada.',
    footer: 'Este é um e-mail automático, por favor não responda a esta mensagem.'
  }
};

function buildResetPasswordEmail(lang, username, link) {
  const tr = RESET_I18N[lang] || RESET_I18N.es;
  const safeUser = escHtml(username);
  const safeLink = escHtml(link);
  const html = '' +
'<!DOCTYPE html><html lang="' + lang + '"><head><meta charset="utf-8">' +
'<meta name="viewport" content="width=device-width,initial-scale=1">' +
'<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">' +
'<title>' + tr.subject + '</title></head>' +
'<body style="margin:0;padding:0;background-color:#0b0b0d;-webkit-text-size-adjust:100%;">' +
'<div style="display:none;max-height:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;color:#0b0b0d;">' + tr.preheader + '&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>' +
'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#0b0b0d;padding:32px 16px;">' +
'<tr><td align="center">' +
'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background-color:#151517;border-radius:16px;border:1px solid #2a2a2e;overflow:hidden;font-family:Segoe UI,Helvetica,Arial,sans-serif;">' +

'<tr><td style="padding:32px 32px 0 32px;text-align:center;">' +
'<div style="display:inline-block;width:52px;height:52px;border-radius:14px;background:linear-gradient(135deg,#e11d2a,#a10f19);line-height:52px;font-size:24px;">🔥</div>' +
'<div style="margin-top:14px;font-size:18px;font-weight:700;color:#ffffff;letter-spacing:.5px;">KYNEX<span style="color:#e11d2a;">PANEL</span></div>' +
'</td></tr>' +

'<tr><td style="padding:28px 32px 0 32px;">' +
'<div style="font-size:11px;font-weight:700;letter-spacing:1.5px;color:#e11d2a;text-align:center;margin-bottom:14px;">' + tr.eyebrow + '</div>' +
'<h1 style="margin:0 0 16px 0;font-size:20px;line-height:1.4;color:#ffffff;font-weight:600;text-align:center;">' + tr.hello + ' ' + safeUser + '</h1>' +
'<p style="margin:0 0 24px 0;font-size:14.5px;line-height:1.7;color:#b8b8bd;text-align:center;">' + tr.intro + '</p>' +
'</td></tr>' +

'<tr><td style="padding:0 32px;">' +
'<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">' +
'<a href="' + safeLink + '" target="_blank" style="display:inline-block;background-color:#e11d2a;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 32px;border-radius:10px;">' + tr.button + '</a>' +
'</td></tr></table>' +
'</td></tr>' +

'<tr><td style="padding:18px 32px 0 32px;text-align:center;">' +
'<span style="display:inline-block;font-size:12px;color:#7a7a80;">⏱ ' + tr.expiry + '</span>' +
'</td></tr>' +

'<tr><td style="padding:28px 32px 0 32px;">' +
'<div style="height:1px;background-color:#2a2a2e;"></div>' +
'</td></tr>' +

'<tr><td style="padding:20px 32px 0 32px;">' +
'<p style="margin:0 0 8px 0;font-size:12px;color:#7a7a80;">' + tr.altText + '</p>' +
'<p style="margin:0;font-size:12px;color:#e11d2a;word-break:break-all;line-height:1.6;">' +
'<a href="' + safeLink + '" target="_blank" style="color:#e11d2a;text-decoration:underline;">' + safeLink + '</a></p>' +
'</td></tr>' +

'<tr><td style="padding:24px 32px 0 32px;">' +
'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#1c1c1f;border-radius:10px;border:1px solid #2a2a2e;">' +
'<tr><td style="padding:14px 16px;">' +
'<p style="margin:0 0 4px 0;font-size:13px;font-weight:700;color:#e5e5e8;">🛡️ ' + tr.ignoreTitle + '</p>' +
'<p style="margin:0;font-size:12.5px;line-height:1.6;color:#9a9aa0;">' + tr.ignore + '</p>' +
'</td></tr></table>' +
'</td></tr>' +

'<tr><td style="padding:24px 32px 28px 32px;text-align:center;">' +
'<p style="margin:0;font-size:11.5px;color:#5a5a60;">' + tr.footer + '</p>' +
'</td></tr>' +

'</table>' +
'</td></tr>' +
'</table>' +
'</body></html>';
  return { subject: tr.subject, html };
}

async function sendMail(to, subject, html, log) {
  const tr = getTransport(log);
  if (!tr) {
    if (log) {
      if (!warnedOnce) {
        log.warn('MAIL', 'SMTP no configurado (define SMTP_HOST/SMTP_USER/SMTP_PASS en las variables de entorno); no se pudo enviar correo a ' + to);
        warnedOnce = true;
      } else {
        log.warn('MAIL', 'SMTP no configurado; correo no enviado a ' + to);
      }
    }
    return false;
  }
  try {
    await tr.sendMail({ from: SMTP_FROM, to, subject, html });
    if (log) log.ok('MAIL', 'Correo enviado a ' + to + ': ' + subject);
    return true;
  } catch (e) {
    if (log) log.err('MAIL', 'Fallo enviando correo a ' + to + ': ' + e.message);
    return false;
  }
}

module.exports = {
  isConfigured,
  sendMail,
  buildResetPasswordEmail,
  buildPanelLink,
  escHtml
};
