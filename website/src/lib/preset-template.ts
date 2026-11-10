// A small Jinja-compatible template subset shared by the website and the macOS app
// (FineText/Services/PresetTemplate.swift). Keep both implementations in sync; the
// shared cases in preset-template-cases.json are run by both test suites.
//
// Supported:
//   {{ expr }}                       output (missing values render as "")
//   {% if %} / {% elif %} / {% else %} / {% endif %}
//   {# comment #}
//   {{- / -}} / {%- / -%}            trim whitespace on that side
//   Block tags drop the newline after them and the indentation before them
//   (Jinja's trim_blocks + lstrip_blocks), so they can sit on their own lines.
// Expressions: paths (a.b), "strings", 'strings', numbers, true/false/none,
//   not, and, or, ==, !=, <, <=, >, >=, in, parentheses and filters:
//   upper, lower, capitalize, title, trim, length, default(value), replace(a, b).

export type TemplateValue = string | number | boolean | null | undefined | { [key: string]: TemplateValue };

export class TemplateError extends Error {}

type Expr =
  | { k: "lit"; v: TemplateValue }
  | { k: "path"; parts: string[] }
  | { k: "not"; e: Expr }
  | { k: "bin"; op: string; l: Expr; r: Expr }
  | { k: "filter"; name: string; e: Expr; args: Expr[] };

type Node =
  | { t: "text"; v: string }
  | { t: "out"; e: Expr }
  | { t: "if"; branches: { cond: Expr | null; body: Node[] }[] };

export const FILTERS = ["upper", "lower", "capitalize", "title", "trim", "length", "default", "replace"] as const;

// MARK: Lexing

type Raw = { kind: "text" | "out" | "tag"; body: string; trimLeft: boolean; trimRight: boolean };

function lex(source: string): Raw[] {
  const raws: Raw[] = [];
  let i = 0;
  while (i < source.length) {
    const start = source.indexOf("{", i);
    const open = start < 0 ? -1 : ["{{", "{%", "{#"].includes(source.slice(start, start + 2)) ? start : -2;
    if (open === -2) {
      raws.push({ kind: "text", body: source.slice(i, start + 1), trimLeft: false, trimRight: false });
      i = start + 1;
      continue;
    }
    if (open < 0) {
      raws.push({ kind: "text", body: source.slice(i), trimLeft: false, trimRight: false });
      break;
    }
    if (open > i) raws.push({ kind: "text", body: source.slice(i, open), trimLeft: false, trimRight: false });
    const marker = source[open + 1];
    const close = marker === "{" ? "}}" : marker === "%" ? "%}" : "#}";
    const end = source.indexOf(close, open + 2);
    if (end < 0) throw new TemplateError(`Unclosed "${source.slice(open, open + 2)}" at offset ${open}`);
    let body = source.slice(open + 2, end);
    const trimLeft = body.startsWith("-");
    const trimRight = body.endsWith("-") && body.length > (trimLeft ? 1 : 0);
    if (trimLeft) body = body.slice(1);
    if (trimRight) body = body.slice(0, -1);
    if (marker !== "#") raws.push({ kind: marker === "{" ? "out" : "tag", body: body.trim(), trimLeft, trimRight });
    else raws.push({ kind: "tag", body: "#", trimLeft, trimRight });
    i = end + 2;
  }
  // Whitespace control, then trim_blocks/lstrip_blocks for block tags and comments.
  for (let n = 0; n < raws.length; n++) {
    const raw = raws[n];
    if (raw.kind === "text") continue;
    const prev = raws[n - 1];
    const next = raws[n + 1];
    if (prev?.kind === "text") {
      if (raw.trimLeft) prev.body = prev.body.replace(/\s+$/, "");
      else if (raw.kind === "tag") prev.body = prev.body.replace(/(^|\n)[ \t]+$/, "$1");
    }
    if (next?.kind === "text") {
      if (raw.trimRight) next.body = next.body.replace(/^\s+/, "");
      else if (raw.kind === "tag") next.body = next.body.replace(/^\r?\n/, "");
    }
  }
  return raws.filter((raw) => !(raw.kind === "tag" && raw.body === "#"));
}

// MARK: Expressions

type Tok = { k: "str" | "num" | "id" | "op"; v: string };

function tokenize(source: string): Tok[] {
  const toks: Tok[] = [];
  let i = 0;
  while (i < source.length) {
    const c = source[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '"' || c === "'") {
      let value = "";
      i++;
      while (i < source.length && source[i] !== c) {
        if (source[i] === "\\" && i + 1 < source.length) {
          const escaped = source[i + 1];
          value += escaped === "n" ? "\n" : escaped === "t" ? "\t" : escaped;
          i += 2;
        } else value += source[i++];
      }
      if (i >= source.length) throw new TemplateError(`Unterminated string in "${source}"`);
      i++;
      toks.push({ k: "str", v: value });
      continue;
    }
    const number = /^\d+(\.\d+)?/.exec(source.slice(i));
    if (number) { toks.push({ k: "num", v: number[0] }); i += number[0].length; continue; }
    const ident = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(i));
    if (ident) { toks.push({ k: "id", v: ident[0] }); i += ident[0].length; continue; }
    const op = ["==", "!=", "<=", ">="].find((candidate) => source.startsWith(candidate, i)) ?? (/[<>|().,]/.test(c) ? c : null);
    if (!op) throw new TemplateError(`Unexpected "${c}" in "${source}"`);
    toks.push({ k: "op", v: op });
    i += op.length;
  }
  return toks;
}

function parseExpression(source: string): Expr {
  const toks = tokenize(source);
  if (!toks.length) throw new TemplateError("Empty expression");
  let p = 0;
  const peek = () => toks[p];
  const isOp = (v: string) => peek()?.k === "op" && peek().v === v;
  const isWord = (v: string) => peek()?.k === "id" && peek().v === v;
  const expect = (v: string) => {
    if (!isOp(v)) throw new TemplateError(`Expected "${v}" in "${source}"`);
    p++;
  };
  const or = (): Expr => {
    let l = and();
    while (isWord("or")) { p++; l = { k: "bin", op: "or", l, r: and() }; }
    return l;
  };
  const and = (): Expr => {
    let l = not();
    while (isWord("and")) { p++; l = { k: "bin", op: "and", l, r: not() }; }
    return l;
  };
  const not = (): Expr => {
    if (isWord("not")) { p++; return { k: "not", e: not() }; }
    return compare();
  };
  const compare = (): Expr => {
    const l = filtered();
    const t = peek();
    if (t && ((t.k === "op" && ["==", "!=", "<", "<=", ">", ">="].includes(t.v)) || (t.k === "id" && t.v === "in"))) {
      p++;
      return { k: "bin", op: t.v, l, r: filtered() };
    }
    return l;
  };
  const filtered = (): Expr => {
    let e = primary();
    while (isOp("|")) {
      p++;
      const name = peek();
      if (name?.k !== "id") throw new TemplateError(`Expected a filter name in "${source}"`);
      if (!(FILTERS as readonly string[]).includes(name.v)) throw new TemplateError(`Unknown filter "${name.v}"`);
      p++;
      const args: Expr[] = [];
      if (isOp("(")) {
        p++;
        if (!isOp(")")) {
          args.push(or());
          while (isOp(",")) { p++; args.push(or()); }
        }
        expect(")");
      }
      e = { k: "filter", name: name.v, e, args };
    }
    return e;
  };
  const primary = (): Expr => {
    const t = peek();
    if (!t) throw new TemplateError(`Unexpected end of "${source}"`);
    p++;
    if (t.k === "str") return { k: "lit", v: t.v };
    if (t.k === "num") return { k: "lit", v: Number(t.v) };
    if (t.k === "op" && t.v === "(") { const e = or(); expect(")"); return e; }
    if (t.k === "id") {
      if (t.v === "true" || t.v === "True") return { k: "lit", v: true };
      if (t.v === "false" || t.v === "False") return { k: "lit", v: false };
      if (t.v === "none" || t.v === "None") return { k: "lit", v: null };
      const parts = [t.v];
      while (isOp(".")) {
        p++;
        const part = peek();
        if (part?.k !== "id") throw new TemplateError(`Expected a name after "." in "${source}"`);
        parts.push(part.v);
        p++;
      }
      return { k: "path", parts };
    }
    throw new TemplateError(`Unexpected "${t.v}" in "${source}"`);
  };
  const expr = or();
  if (p < toks.length) throw new TemplateError(`Unexpected "${toks[p].v}" in "${source}"`);
  return expr;
}

// MARK: Parsing

export function parseTemplate(source: string): Node[] {
  const raws = lex(source);
  let p = 0;
  const block = (terminators: string[]): { body: Node[]; end: string | null } => {
    const body: Node[] = [];
    while (p < raws.length) {
      const raw = raws[p];
      if (raw.kind === "text") { if (raw.body) body.push({ t: "text", v: raw.body }); p++; continue; }
      if (raw.kind === "out") { body.push({ t: "out", e: parseExpression(raw.body) }); p++; continue; }
      const [word] = raw.body.split(/\s+/, 1);
      if (terminators.includes(word)) return { body, end: word };
      if (word !== "if") throw new TemplateError(`Unknown or unexpected tag "{% ${raw.body} %}"`);
      p++;
      const branches: { cond: Expr | null; body: Node[] }[] = [];
      let cond: Expr | null = parseExpression(raw.body.slice(2));
      for (;;) {
        const inner = block(["elif", "else", "endif"]);
        branches.push({ cond, body: inner.body });
        if (!inner.end) throw new TemplateError(`Missing {% endif %} for "{% ${raw.body} %}"`);
        const tag = raws[p].body;
        p++;
        if (inner.end === "endif") break;
        if (branches.at(-1)!.cond === null) throw new TemplateError("{% else %} must be the last branch");
        cond = inner.end === "elif" ? parseExpression(tag.slice(4)) : null;
      }
      body.push({ t: "if", branches });
    }
    return { body, end: null };
  };
  const result = block([]);
  if (p < raws.length) throw new TemplateError(`Unexpected "{% ${raws[p].body} %}"`);
  return result.body;
}

// MARK: Rendering

const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });
const missing = (v: TemplateValue) => v === undefined || v === null;
const truthy = (v: TemplateValue) =>
  !missing(v) && v !== false && v !== 0 && v !== "" && !(typeof v === "object" && !Object.keys(v!).length);

export function stringify(v: TemplateValue): string {
  if (missing(v)) return "";
  if (typeof v === "boolean") return v ? "True" : "False";
  if (typeof v === "number") return String(v);
  if (typeof v === "object") return "";
  return v;
}

function evaluate(e: Expr, context: Record<string, TemplateValue>): TemplateValue {
  switch (e.k) {
    case "lit": return e.v;
    case "path": {
      let value: TemplateValue = context;
      for (const part of e.parts) value = value && typeof value === "object" ? value[part] : undefined;
      return value;
    }
    case "not": return !truthy(evaluate(e.e, context));
    case "bin": {
      const l = evaluate(e.l, context);
      if (e.op === "and") return truthy(l) ? evaluate(e.r, context) : l;
      if (e.op === "or") return truthy(l) ? l : evaluate(e.r, context);
      const r = evaluate(e.r, context);
      switch (e.op) {
        case "==": return (missing(l) && missing(r)) || l === r;
        case "!=": return !((missing(l) && missing(r)) || l === r);
        case "in": return typeof r === "string" ? r.includes(stringify(l)) : !!r && typeof r === "object" && stringify(l) in r;
        default: {
          if (typeof l !== typeof r || (typeof l !== "number" && typeof l !== "string")) return false;
          const [a, b] = [l as number | string, r as number | string];
          return e.op === "<" ? a < b : e.op === "<=" ? a <= b : e.op === ">" ? a > b : a >= b;
        }
      }
    }
    case "filter": {
      const value = evaluate(e.e, context);
      const args = e.args.map((arg) => evaluate(arg, context));
      const text = stringify(value);
      switch (e.name) {
        case "upper": return text.toUpperCase();
        case "lower": return text.toLowerCase();
        case "capitalize": return text ? text[0].toUpperCase() + text.slice(1).toLowerCase() : text;
        case "title": return text.toLowerCase().replace(/(^|[^A-Za-z0-9'])([a-z])/g, (_, a, b) => a + b.toUpperCase());
        case "trim": return text.trim();
        // Grapheme count, like Swift's String.count.
        case "length": return typeof value === "object" && value ? Object.keys(value).length : [...graphemes.segment(text)].length;
        case "default": return missing(value) || value === "" ? args[0] : value;
        case "replace": return text.split(stringify(args[0])).join(stringify(args[1]));
      }
      throw new TemplateError(`Unknown filter "${e.name}"`);
    }
  }
}

function renderNodes(nodes: Node[], context: Record<string, TemplateValue>): string {
  let out = "";
  for (const node of nodes) {
    if (node.t === "text") out += node.v;
    else if (node.t === "out") out += stringify(evaluate(node.e, context));
    else {
      const branch = node.branches.find((b) => b.cond === null || truthy(evaluate(b.cond, context)));
      if (branch) out += renderNodes(branch.body, context);
    }
  }
  return out;
}

export function renderTemplate(source: string, context: Record<string, TemplateValue>): string {
  return renderNodes(parseTemplate(source), context);
}

/** Every variable path referenced anywhere in the template, including untaken branches. */
export function templateVariables(source: string): string[] {
  const seen = new Set<string>();
  const visitExpr = (e: Expr): void => {
    if (e.k === "path") seen.add(e.parts.join("."));
    else if (e.k === "not") visitExpr(e.e);
    else if (e.k === "bin") { visitExpr(e.l); visitExpr(e.r); }
    else if (e.k === "filter") { visitExpr(e.e); e.args.forEach(visitExpr); }
  };
  const visit = (nodes: Node[]): void => {
    for (const node of nodes) {
      if (node.t === "out") visitExpr(node.e);
      else if (node.t === "if") node.branches.forEach((b) => { if (b.cond) visitExpr(b.cond); visit(b.body); });
    }
  };
  visit(parseTemplate(source));
  return [...seen].sort();
}
