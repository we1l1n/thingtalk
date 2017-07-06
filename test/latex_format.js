const Q = require('q');
const fs = require('fs');
const deq = require('deep-equal');

const AppCompiler = require('../lib/compiler');
const AppGrammar = require('../lib/grammar_api');
const SchemaRetriever = require('../lib/schema');
const prettyprint = require('../lib/prettyprint');
const Ast = require('../lib/ast');
const SEMPRESyntax = require('../lib/sempre_syntax');

const _mockSchemaDelegate = require('./mock_schema_delegate');
const ThingpediaClientHttp = require('./http_client');
const db = require('./db');

function latexprintLocation(l) {
    if (l.isAbsolute)
        return `\\text{makeLocation}(${l.lat}, ${l.lon})`;
    else
        return `\\texttt{location.${l.relativeTag}}`;
}

function cleanIdent(v) {
    return v.replace(/_/g, '\\_');
}

function latexprintValue(v, renames) {
    if (v.isVarRef && v.name in renames)
        return 'v_' + renames[v.name];
    if (v.isVarRef)
        return `\\textit{${cleanIdent(v.name)}}`;
    if (v.isUndefined)
        return '\\texttt{undefined}';
    if (v.isNull)
        return '\\texttt{null}';
    if (v.isLocation)
        return latexprintLocation(v.value);
    if (v.isString)
        return '\\text{``' + v.value + `''}`;
    if (v.isBoolean)
        return v.value ? '\\texttt{true}' : '\\texttt{false}';
    if (v.isMeasure)
        return v.value + v.unit;
    if (v.isNumber)
        return v.value;
    if (v.isDate)
        return '\\text{makeDate}(' + v.value.getTime() + ')';
    if (v.isTime)
        return '\\text{makeTime}(' + v.hour + ',' + v.minute + ')';
    if (v.isEntity)
        return `\\texttt{"${v.value}"\\^{}\\^{}${v.type}}`;
    if (v.isEvent)
        return '\\texttt{event}';
    return String(v);
}

function isFilterInfix(op) {
    switch (op) {
    case '=':
    case '!=':
    case '>':
    case '>=':
    case '<':
    case '<=':
        return true;
    default:
        return false;
    }
}

function opToLatex(op) {
    switch (op) {
    case '=':
    case '>':
    case '<':
        return op;
    case '!=':
        return '\\ne';
    case '>=':
        return '\\ge';
    case '<=':
        return '\\le';
    case '=~':
        return '\\texttt{substr}';
    default:
        return `\\texttt{${op}}`;
    }
}

function latexprintFilter(expr, renames) {
    return (function recursiveHelper(expr) {
        if (expr.isTrue)
            return '\\texttt{true}';
        if (expr.isFalse)
            return '\\texttt{false}';
        if (expr.isAnd)
            return expr.operands.map(recursiveHelper).join(`\\texttt{ \\&\\& }`);
        if (expr.isOr)
            return expr.operands.map(recursiveHelper).join(`\\texttt{ || }`);
        if (expr.isNot)
            return `\\texttt{!(}` + recursiveHelper(expr.expr) + `\\texttt{)}`;

        let filter = expr.filter;
        if (isFilterInfix(filter.operator)) {
            return `\\textit{${cleanIdent(filter.name)}} ${opToLatex(filter.operator)} ${latexprintValue(filter.value, renames)}`;
        } else {
            return `\\textit{${cleanIdent(filter.name)}} ${opToLatex(filter.operator)} ${latexprintValue(filter.value, renames)}`;
        }
    })(expr);
}

function latexprintInvocation(invocation, state) {
    for (let out_params of invocation.out_params)
        state.renames[out_params.name] = state.idx++;
    let renames = state.renames;
    return (`@\\text{${cleanIdent(invocation.selector.kind)}.${cleanIdent(invocation.channel)}}(`
        + invocation.in_params.map((ip) => `\\textit{${cleanIdent(ip.name)}} = ${latexprintValue(ip.value, renames)}`).join(', ')
        + ')' + (invocation.filter.isTrue ? '' : ', ' + latexprintFilter(invocation.filter, renames))
        + invocation.out_params.map((op) => `, v_${state.renames[op.name]} := \\textit{${cleanIdent(op.value)}}`).join(''));
}

function latexprintTrigger(trigger, state) {
    if (!trigger)
        return '\\texttt{now}';

    return latexprintInvocation(trigger, state);
}
function latexprintAction(action, state) {
    if (!action || action.selector.isBuiltin)
        return '\\texttt{notify}';

    return latexprintInvocation(action, state);
}

function latexprintRule(rule) {
    let state = { renames: {}, idx: 0 };
    return (latexprintTrigger(rule.trigger, state) + ` &\\Rightarrow ` +
        (rule.queries.length > 0 ? latexprintInvocation(rule.queries[0], state) + `\\nonumber\\\\` + '\n' + `&\\Rightarrow ` : '')
        + latexprintAction(rule.actions[0], state));
}

function latexprintProgram(prog) {
    return `\\begin{align}\n` + prog.rules.map(latexprintRule).join('\n') + `\n\\end{align}`;
}

function main() {
    var input = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (buf) => {
        input += buf;
    });
    process.stdin.on('end', () => {
        console.log(latexprintProgram(AppGrammar.parse(input)));
    });
}
main();
