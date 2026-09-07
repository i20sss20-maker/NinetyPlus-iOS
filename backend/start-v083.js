import { readFile, writeFile } from 'node:fs/promises';

// Build on the proven v0.8.x transformation without duplicating its server patch.
// Transformations are loaded as text so nested template literals remain data until
// the generated start script is parsed.
const original = await readFile(new URL('./start-v08.js', import.meta.url), 'utf8');
const extensionRaw = await readFile(new URL('./v083-coach-patch.txt', import.meta.url), 'utf8');
const speedRaw = await readFile(new URL('./v087-speed-patch.txt', import.meta.url), 'utf8');
// Text inserted into a template literal is parsed twice. Keep the SPL HTML cleaner
// free of generated regex literals so escaped newlines cannot become invalid source.
const extension = extensionRaw
  .replace("if (!insideTag) out+=ch;", "if (!insideTag) out+=(ch.charCodeAt(0)<=32?' ':ch);")
  .replace(".split(/ +|\\n|\\r|\\t/).filter(Boolean).join(' ')", ".split(' ').filter(Boolean).join(' ')");
const marker = "const generated = new URL('./.generated-server-v08.js', import.meta.url);";
if (!original.includes(marker)) throw new Error('v0.8.3 bootstrap marker missing');

const generatedStart = new URL('./.generated-start-v083.js', import.meta.url);
await writeFile(generatedStart, original.replace(marker, extension + '\n' + speedRaw + '\n' + marker), 'utf8');
await import(generatedStart.href + `?v=${Date.now()}`);
