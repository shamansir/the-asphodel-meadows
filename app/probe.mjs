// Runs the Elm probe headlessly. See src/Probe.elm.
//   elm make src/Probe.elm --output=probe.js && node probe.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { Elm } = require("./probe.js");

const chunk = readFileSync(new URL("../demo-world/chunk.json", import.meta.url), "utf8");
const app = Elm.Probe.init({ flags: chunk });
app.ports.out.subscribe((s) => console.log(s));
