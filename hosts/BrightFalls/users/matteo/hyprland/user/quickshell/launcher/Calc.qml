pragma Singleton

import QtQuick
import Quickshell

// The launcher's calculator: a recursive-descent parser for arithmetic.
// The text is never handed to a JavaScript or shell interpreter.
Singleton {
    // { ok: true, value, text } for a valid expression, where `text` is the
    // result as it is shown and copied; { ok: false, hint } otherwise.
    //
    // Grammar, loosest first; `^` is right-associative and binds tighter
    // than unary minus, so -2^2 is -4 and 2^-1 is 0.5:
    //   expr    = term (("+" | "-") term)*
    //   term    = unary (("*" | "/" | "%") unary)*
    //   unary   = ("-" | "+") unary | power
    //   power   = primary ("^" unary)?
    //   primary = number | constant | function "(" expr ")" | "(" expr ")"
    function evaluate(input) {
        if (input.trim() === "")
            return { ok: false, hint: "Type an expression: + - * / % ^ ( ), sqrt abs round floor ceil, pi e" };
        let tokens;
        try {
            tokens = tokenize(input);
        } catch (error) {
            return { ok: false, hint: error.message };
        }
        let pos = 0;
        const peek = () => tokens[pos];
        const fail = message => {
            throw new Error(message);
        };
        const unexpected = () => peek() ? fail(`Unexpected ${peek().text}`) : fail("Incomplete expression");
        const take = text => {
            if (peek()?.text !== text)
                unexpected();
            pos++;
        };

        function expr() {
            let value = term();
            while (peek()?.text === "+" || peek()?.text === "-")
                value = tokens[pos++].text === "+" ? value + term() : value - term();
            return value;
        }
        function term() {
            let value = unary();
            while (peek()?.text === "*" || peek()?.text === "/" || peek()?.text === "%") {
                const op = tokens[pos++].text;
                const right = unary();
                if (op === "*") {
                    value *= right;
                } else if (right === 0) {
                    fail("Division by zero");
                } else {
                    value = op === "/" ? value / right : value % right;
                }
            }
            return value;
        }
        function unary() {
            if (peek()?.text === "-") {
                pos++;
                return -unary();
            }
            if (peek()?.text === "+") {
                pos++;
                return unary();
            }
            return power();
        }
        function power() {
            const base = primary();
            if (peek()?.text !== "^")
                return base;
            pos++;
            return Math.pow(base, unary());
        }
        function primary() {
            const token = peek();
            if (!token)
                unexpected();
            if (token.kind === "number") {
                pos++;
                return token.value;
            }
            if (token.kind === "name") {
                pos++;
                if (token.text === "pi")
                    return Math.PI;
                if (token.text === "e")
                    return Math.E;
                const fn = ({
                        sqrt: Math.sqrt,
                        abs: Math.abs,
                        round: Math.round,
                        floor: Math.floor,
                        ceil: Math.ceil
                    })[token.text];
                if (!["sqrt", "abs", "round", "floor", "ceil"].includes(token.text))
                    fail(`Unknown name ${token.text}`);
                take("(");
                const argument = expr();
                take(")");
                return fn(argument);
            }
            if (token.text === "(") {
                pos++;
                const value = expr();
                take(")");
                return value;
            }
            unexpected();
        }

        let value;
        try {
            value = expr();
            if (pos < tokens.length)
                unexpected();
        } catch (error) {
            return { ok: false, hint: error.message };
        }
        if (Number.isNaN(value))
            return { ok: false, hint: "Not a real number" };
        if (!Number.isFinite(value))
            return { ok: false, hint: "Out of range" };
        return { ok: true, value, text: format(value) };
    }

    function tokenize(input) {
        const tokens = [];
        const pattern = /\s*(?:((?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)|([a-zA-Z]+)|([-+*/%^()]))/y;
        let at = 0;
        while (at < input.length) {
            if (/^\s*$/.test(input.slice(at)))
                break;
            pattern.lastIndex = at;
            const m = pattern.exec(input);
            if (!m)
                throw new Error(`Unexpected ${input.slice(at).trim()[0]}`);
            if (m[1] !== undefined)
                tokens.push({ kind: "number", text: m[1], value: parseFloat(m[1]) });
            else
                tokens.push(m[2] !== undefined ? { kind: "name", text: m[2].toLowerCase() } : { kind: "op", text: m[3] });
            at = pattern.lastIndex;
        }
        return tokens;
    }

    // Plain digits, no grouping, so the shown text is what gets copied.
    // Integers JavaScript holds exactly are shown in full; anything else is
    // rounded to 15 significant digits, which drops binary noise such as
    // 0.1 + 0.2 = 0.30000000000000004 and is all a double reliably holds;
    // from 1e15 up that is fewer digits than the integer part, so those are
    // written with an exponent rather than padded with made-up digits.
    function format(value) {
        if (value === 0)
            return "0";
        if (Number.isSafeInteger(value))
            return String(value);
        const rounded = Number(value.toPrecision(15));
        const magnitude = Math.abs(rounded);
        return magnitude >= 1e15 || magnitude < 1e-6 ? rounded.toExponential() : String(rounded);
    }
}
