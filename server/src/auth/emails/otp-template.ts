import { readFileSync } from "node:fs";

// Keep a server-owned copy: the production image does not include the iOS app.
const logo = readFileSync(new URL("./assets/hybrd-mark.png", import.meta.url));
const logoContentId = "hybrd-mark";

// Canonical palette from the iOS BrandSheet asset.
const colors = {
  obsidian: "#0D0D0E",
  terra: "#FF6B3D",
  sand: "#F4EDE7",
  stone: "#CBD5E1",
  mist: "#F8FAFC",
  muted: "#56565E",
};

export function otpMessage(otp: string) {
  if (otp.length !== 6 || !/^\d{6}$/.test(otp))
    throw new Error("Invalid authentication code format.");

  return {
    subject: "Your hybrd sign-in code",
    text: `Sign in to hybrd\n\nYour one-time code: ${otp}\n\nEnter this code in the hybrd app to create your account or sign in.\n\nThis code expires in 10 minutes and works once. Never share it.\n\nIf you didn't request this code, you can safely ignore this email.`,
    html: `<!doctype html>
<html lang="en" dir="ltr">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <meta name="supported-color-schemes" content="light dark">
    <title>Your hybrd sign-in code</title>
    <style>
      :root { color-scheme: light dark; supported-color-schemes: light dark; }
      body, table, td, p { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
      table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
      @media only screen and (max-width: 480px) {
        .outer { padding: 24px 16px !important; }
        .inset { padding-left: 24px !important; padding-right: 24px !important; }
        .heading { font-size: 30px !important; line-height: 36px !important; }
        .code { font-size: 32px !important; letter-spacing: 6px !important; }
      }
      @media (prefers-color-scheme: dark) {
        .canvas { background-color: #171719 !important; }
        .surface { background-color: #242426 !important; }
        .ink { color: ${colors.mist} !important; }
        .muted { color: ${colors.stone} !important; }
        .code-box { background-color: ${colors.obsidian} !important; }
        .divider { border-color: #414147 !important; }
      }
    </style>
  </head>
  <body class="canvas" style="margin: 0; padding: 0; width: 100%; background-color: ${colors.sand};">
    <div lang="en" dir="ltr" aria-hidden="true" style="display: none; font-size: 1px; line-height: 1px; color: ${colors.sand}; max-height: 0; max-width: 0; opacity: 0; overflow: hidden; mso-hide: all;">Your one-time code to securely sign in to hybrd. Valid for 10 minutes.</div>
    <table lang="en" dir="ltr" role="presentation" class="canvas" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${colors.sand}" style="width: 100%; background-color: ${colors.sand}; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;">
      <tr>
        <td class="outer" align="center" style="padding: 48px 24px;">
          <!--[if mso]><table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
          <table role="presentation" class="surface" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${colors.mist}" style="width: 100%; max-width: 560px; background-color: ${colors.mist}; border-radius: 20px; border-spacing: 0;">
            <tr>
              <td class="inset" bgcolor="${colors.obsidian}" style="padding: 24px 40px; background-color: ${colors.obsidian}; border-radius: 20px 20px 0 0; border-bottom: 4px solid ${colors.terra};">
                <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td width="52" style="width: 52px;"><img src="cid:${logoContentId}" width="52" height="52" alt="" style="display: block; width: 52px; height: 52px; border: 0;"></td>
                    <td style="padding-left: 12px; color: ${colors.mist}; font-size: 28px; line-height: 34px; font-weight: 700; letter-spacing: -1px;">hybrd</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td class="inset" style="padding: 36px 40px 40px;">
                <p class="muted" style="margin: 0 0 12px; color: ${colors.muted}; font-size: 11px; line-height: 16px; font-weight: 700; letter-spacing: 2px;">YOUR TRAINING STARTS HERE</p>
                <h1 class="heading ink" style="margin: 0 0 16px; color: ${colors.obsidian}; font-size: 34px; line-height: 40px; font-weight: 700; letter-spacing: -1px;">Sign in to hybrd.</h1>
                <p class="muted" style="margin: 0 0 28px; color: ${colors.muted}; font-size: 16px; line-height: 26px;">Enter this code in the hybrd app to create your account or sign in.</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width: 100%;">
                  <tr>
                    <td class="code-box" align="center" bgcolor="${colors.sand}" style="padding: 24px 12px; background-color: ${colors.sand}; border-radius: 12px;">
                      <p class="muted" style="margin: 0 0 10px; color: ${colors.muted}; font-size: 11px; line-height: 16px; font-weight: 700; letter-spacing: 1.5px;">YOUR ONE-TIME CODE</p>
                      <p class="code ink" dir="ltr" style="margin: 0; color: ${colors.obsidian}; font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace; font-size: 40px; line-height: 52px; font-weight: 700; letter-spacing: 8px; white-space: nowrap;">${otp}</p>
                    </td>
                  </tr>
                </table>
                <p class="muted" style="margin: 16px 0 28px; color: ${colors.muted}; text-align: center; font-size: 13px; line-height: 20px;">Expires in <strong class="ink" style="color: ${colors.obsidian};">10 minutes</strong>. Works once.</p>
                <p class="ink" style="margin: 0 0 24px; color: ${colors.obsidian}; font-size: 14px; line-height: 22px;">Keep it just for you. Never share your sign-in code.</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width: 100%;">
                  <tr>
                    <td class="divider" style="padding-top: 24px; border-top: 1px solid ${colors.stone};">
                      <p class="muted" style="margin: 0; color: ${colors.muted}; font-size: 13px; line-height: 21px;">Didn't request this code?<br>You can safely ignore this email.</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
          <!--[if mso]></td></tr></table><![endif]-->
          <p class="muted" style="margin: 24px 0 0; color: ${colors.muted}; font-size: 11px; line-height: 18px; letter-spacing: 1px;">HYBRD &nbsp;&middot;&nbsp; SECURE ACCOUNT ACCESS</p>
        </td>
      </tr>
    </table>
  </body>
</html>`,
    // CID embeds the original logo without an external image host or tracking URL.
    attachments: [
      {
        filename: "hybrd-mark.png",
        content: logo.toString("base64"),
        content_type: "image/png",
        content_id: logoContentId,
      },
    ],
  };
}
