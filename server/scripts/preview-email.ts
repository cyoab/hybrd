import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { otpMessage } from "../src/auth/emails/otp-template";

// A fixed, nonfunctional code. This command neither creates a challenge nor sends email.
const message = otpMessage("024681");
let html = message.html;
for (const attachment of message.attachments) {
  html = html.replaceAll(
    `cid:${attachment.content_id}`,
    `data:${attachment.content_type};base64,${attachment.content}`,
  );
}
const directory = new URL("../../dist/emails/", import.meta.url);
await mkdir(directory, { recursive: true });
const preview = new URL("otp.html", directory);
await Bun.write(preview, html);
await Bun.write(new URL("otp.txt", directory), message.text);
console.log(`Email preview: ${fileURLToPath(preview)}`);
