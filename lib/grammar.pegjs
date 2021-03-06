// -*- mode: js; indent-tabs-mode: nil; js-basic-offset: 4 -*-
//
// This file is part of ThingTalk
//
// Copyright 2015-2018 The Board of Trustees of the Leland Stanford Junior University
//
// Author: Giovanni Campagna <gcampagn@cs.stanford.edu>
//
// See COPYING for details

{
    var Units = require('thingtalk-units');

    var assert = require('assert');
    var Ast = require('./ast');
    var Type = require('./type');
    var { optimizeFilter, optimizeProgram } = require('./optimize');

    function take(array, idx) {
        return array.map(function(v) { return v[idx]; });
    }

    function checkExampleAnnotations(annotations) {
        let id = -1;
        let utterances = [];
        let preprocessed = [];
        let other = {};

        for (let annotation of annotations) {
            if (annotation.type === 'impl') {
                if (annotation.name === 'id') {
                    if (!annotation.value.isNumber)
                        return error(`Example id annotation must be a number`);
                    id = annotation.value.value;
                } else {
                    other[annotation.name] = annotation.value.toJS();
                }
            } else {
                if (!annotation.value.isArray && !annotation.value.isString)
                    return error(`An array is expected for ${annotation.name} annotation`);
                if (!annotation.value.isArray)
                    annotation.value = Ast.Value.Array([annotation.value]);

                switch (annotation.name) {
                case 'utterances':
                    utterances.push(...annotation.value.value.map((v) => v.value));
                    break;
                case 'preprocessed':
                    preprocessed.push(...annotation.value.value.map((v) => v.value));
                    break;
                default:
                    return error(`Invalid example annotation ${annotation.name}, expected utterances or preprocessed`);
                }
            }
        }

        return [id, utterances, preprocessed, other];
    }

    // split annotations between nl and impl
    function splitAnnotations(annotations) {
        const nl_annotations = {};
        const impl_annotations = {};
        if (annotations) {
            take(annotations, 1).forEach((a) => {
                if (a.type === 'nl')
                    nl_annotations[a.name] = a.value.toJS();
                else if (a.type === 'impl')
                    impl_annotations[a.name] = a.value;
                else
                    throw new TypeError();
            });
        }
        return [nl_annotations, impl_annotations];
    }

    function makeInput(statements, principal) {
        const classes = [];
        const datasets = [];
        const declarations = [];
        const commandsOrRules = [];
        const oninputs = [];

        for (let stmt of statements) {
            if (stmt.isClassDef)
                classes.push(stmt);
            else if (stmt.isDataset)
                datasets.push(stmt);
            else if (stmt.isDeclaration)
                declarations.push(stmt);
            else if (stmt.isOnInput && oninputs.length > 0)
                error(`Multiple oninput statements in the same scope are not allowed`);
            else if (stmt.isOnInput)
                oninputs.push(...stmt);
            else
                commandsOrRules.push(stmt);
        }

        if (datasets.length > 0) {
            if (declarations.length > 0 || commandsOrRules.length > 0 || oninputs.length > 0)
                error(`Cannot mix dataset with ThingTalk statements other than class`);
            if (principal !== null)
                error(`Cannot have dataset statements in remote ThingTalk programs`);
            return new Ast.Input.Library(location(), classes, datasets);
        }
        if (classes.length > 0 && declarations.length === 0 && commandsOrRules.length === 0 && oninputs.length === 0 && principal === null)
            return new Ast.Input.Library(location(), classes, datasets);

        return optimizeProgram(new Ast.Input.Program(location(), classes, declarations, commandsOrRules, principal, oninputs));
    }
}

input = bookkeeping_stmt / permission_rule / short_remote_program / wrapped_program / simple_program

bookkeeping_stmt = _ 'bookkeeping' _ '(' _ intent:bookkeeping_intent _ ')' _ ';' _ {
    return new Ast.Input.Bookkeeping(location(), intent);
}
bookkeeping_intent = 'commands' _ '(' _ 'device' _ '=' _ device:(entity_value / undefined_value) _ ',' _ 'category' _ '=' _ category:literal_string _ ')' {
    return new Ast.BookkeepingIntent.CommandList(location(), device, category);
} / 'commands' _ '(' _  'category' _ '=' _ category:literal_string _ ',' _ 'device' _ '=' _ device:(entity_value / undefined_value) _ ')' {
    return new Ast.BookkeepingIntent.CommandList(location(), device, category);
} / 'commands' _ '(' _  'category' _ '=' _ category:literal_string _ ')' {
    return new Ast.BookkeepingIntent.CommandList(location(), new Ast.Value.Undefined(true), category);
} / 'choice' _ '(' _ value:literal_number _ ')' {
    return new Ast.BookkeepingIntent.Choice(location(), value);
} / 'answer' _ '(' _ value:value _ ')' {
    return new Ast.BookkeepingIntent.Answer(location(), value);
} / 'predicate' _ '(' _ predicate:or_expr _ ')' {
    return new Ast.BookkeepingIntent.Predicate(location(), predicate);
} / type:ident {
    return new Ast.BookkeepingIntent.Special(location(), type);
}

short_remote_program = _ principal:program_principal _ statement:top_level_statement {
    return makeInput([statement], principal);
}

simple_program = _ statements:(top_level_statement _)* {
    return makeInput(take(statements, 0), null);
}
wrapped_program = _ principal:program_principal? _ '{' _ statements:(top_level_statement _)* '}' _ {
    return makeInput(take(statements, 0), principal);
}

program_principal = 'executor' _ '=' _ value:('self' / value) _ ':' {
    if (value === 'self')
        return null;
    else if (value.isString) // for compat and ease of use, a raw string is a contact name
        return Ast.Value.Entity(value.value, 'tt:username', null);
    else
        return value;
}

permission_function = kind:class_name _ '.' _ '*' {
    return new Ast.PermissionFunction.ClassStar(location(), kind);
} / fn:short_function_name _ filter:(',' _ or_expr _)? {
    let [selector, channel] = fn;
    let kind = selector.kind;
    if (filter === null)
        filter = Ast.BooleanExpression.True;
    else
        filter = filter[2];
    return new Ast.PermissionFunction.Specified(location(), kind, channel, optimizeFilter(filter), null);
} / '*' { return Ast.PermissionFunction.Star }

permission_rule = _ principal:or_expr _ ':' _ first:(permission_function / 'now') _ '=>' _ second:(permission_function / 'notify') _  ';'? {
    if (first === 'now')
        first = Ast.PermissionFunction.Builtin;
    if (second === 'notify')
        second = Ast.PermissionFunction.Builtin;
    if (first === Ast.PermissionFunction.Builtin && second === Ast.PermissionFunction.Builtin)
        throw error('Permission function specifies no access');
    return new Ast.PermissionRule(location(), optimizeFilter(principal), first, second);
}

// Class declarations
full_class_name = '@' first_name:classident _ rest_names:('.' _ classident _ !(_ ('(' / ')' / '=>')))* {
    return first_name + (rest_names.length > 0 ? ('.' + take(rest_names, 2).join('.')) : '');
}

full_class_name_list = first:full_class_name _ rest:(',' _ full_class_name _)* {
    return [first].concat(take(rest, 2))
}

class_name = '@' first_name:classident _ rest_names:('.' _ classident _)* {
    return first_name + (rest_names.length > 0 ? ('.' + take(rest_names, 2).join('.')) : '');
}

class_def = is_abstract:('abstract' __ )? 'class' _ name:class_name _ extends_:('extends' __ full_class_name_list)? annotations:(_ annotation)* _ '{' _ members:class_member* _ '}' _ ';'? {
    const queries = {};
    const actions = {};
    const macros = {};
    const imports = [];

    for (var ast of members) {
        if (ast instanceof Ast.FunctionDef) {
          switch (ast.functionType) {
          case 'query':
              queries[ast.name] = ast;
              break;
          case 'action':
              actions[ast.name] = ast;
              break;
          }
        } else if (ast instanceof Ast.ImportStmt) {
          imports.push(ast);
        } else if (ast instanceof Ast.ComputeDef) {
          macros[ast.name] = ast;
        }
    }

    const [nl, impl] = splitAnnotations(annotations);
    const options = { is_abstract: !!is_abstract };
    return new Ast.ClassDef(location(), name, extends_ !== null ? extends_[2] : null, { queries, actions, imports, macros }, { nl, impl }, options);
}

query_modifiers = 'monitorable' __ 'list' !identchar {
  return [true, true];
} / 'list' __ 'monitorable' !identchar {
  return [true, true];
} / 'list' !identchar {
  return [false, true];
} / 'monitorable' !identchar {
  return [true, false];
}

class_member = v:(function_def / import_class_stmt / import_mixin_stmt / compute_def) _ { return v; }

import_class_stmt = 'import' __ 'class' __ name:class_name _ alias:('as' __ ident)? _ ';' {
  return new Ast.ImportStmt.Class(location(), name, alias !== null ? alias[2] : null);
}
import_mixin_stmt = 'import' __ first:ident _ rest:(',' _ ident _)* 'from' __ name:class_name _ in_params:input_param_list _ ';' {
  return new Ast.ImportStmt.Mixin(location(), [first].concat(take(rest, 2)), name, in_params);
}

compute_def = 'compute' __ name:ident _ args:function_param_decl_list _  ':' _ 'Boolean' _ ':=' _ compute:or_expr _ annotations: ( _ annotation _)* ';' _ {
    const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
    return new Ast.ComputeDef(location(), name, Type.Boolean, args, compute, nl_annotations, impl_annotations);
} / 'compute' __ name:ident _ args:function_param_decl_list _ ':' _ type:type_ref _ ':=' _ compute:value _ annotations: ( _ annotation _)* ';' _ {
    const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
    return new Ast.ComputeDef(location(), name, type, args, compute, nl_annotations, impl_annotations);
}

function_name_list = first:ident _ rest:(',' _ ident _)* {
    return [first].concat(take(rest, 2))
}
function_def = modifiers:query_modifiers? _ type:('query' / 'action') __ name:ident _ extends_:('extends' _ function_name_list _ )? args:function_param_decl_list _ annotations: ( _ annotation _)* ';' _ {
    let [is_monitorable, is_list] = modifiers || [false, false];
    const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
    return new Ast.FunctionDef(location(), type, null, name, extends_ !== null ? extends_[2] : null, { is_list, is_monitorable }, args, { nl:nl_annotations, impl:impl_annotations });
}
function_param_decl_list = '(' _ ')' { return []; } /
    '(' _ first:function_param_decl _ rest:(',' _ function_param_decl _)* ')' {
    return [first].concat(take(rest, 2));
}
function_param_decl = direction:param_direction __ name:ident _ ':' _ type:type_ref annotations:( _ annotation _)* {
    const [nl, impl] = splitAnnotations(annotations);
    return new Ast.ArgumentDef(location(), direction, name, type, { nl, impl });
}
param_direction = 'in' __ 'req' { return 'in req'; } / 'in' __ 'opt' { return 'in opt'; } /
    'out' { return 'out'; }


// Dataset & Thingpedia Definition
dataset_name = ident / name:class_name { return '@' + name; }

dataset = _ 'dataset' _ name:dataset_name _ lan:('language' _ literal_string _)? '{' _ examples:(_ example _)* _ '}' _ ';'? {
    return new Ast.Dataset(location(), name, lan? lan[2] : 'en' , take(examples, 1), {});
}

example = 'stream'  _ params:(lambda_param_decl_list)? _ ':=' _ stream:stream _ annotations:(annotation _)* _ ';' {
    const [id, utterances, preprocessed, other] = checkExampleAnnotations(take(annotations, 0));
    return new Ast.Example(location(), id, 'stream', params ? params : [], stream, utterances, preprocessed, other);
} / 'query'  _ params:(lambda_param_decl_list)? _ ':=' _ query:table _ annotations:(annotation _)* _ ';' {
    const [id, utterances, preprocessed, other] = checkExampleAnnotations(take(annotations, 0));
    return new Ast.Example(location(), id, 'query', params ? params : [], query, utterances, preprocessed, other);
} / 'action'  _ params:(lambda_param_decl_list)? _ ':=' _ action:action _ annotations:(annotation _)* _ ';' {
    const [id, utterances, preprocessed, other] = checkExampleAnnotations(take(annotations, 0));
    return new Ast.Example(location(), id, 'action', params ? params : [], action, utterances, preprocessed, other);
} / 'program'  _ params:(lambda_param_decl_list)? _ ':=' _ '{' _ statements:(statement _)+ '}' _ annotations:(annotation _)* _ ';' {
    const [id, utterances, preprocessed, other] = checkExampleAnnotations(take(annotations, 0));
    return new Ast.Example(location(), id, 'program', params ? params : [], makeInput(take(statements, 0)), utterances, preprocessed, other);
} / 'program'  _ params:(lambda_param_decl_list)? _ ':=' _ rule:rule_body _ annotations:(annotation _)* _ ';' {
    const [id, utterances, preprocessed, other] = checkExampleAnnotations(take(annotations, 0));
    return new Ast.Example(location(), id, 'program', params ? params : [],
        (new Ast.Program(location(), [], [], [rule], null)).optimize(), utterances, preprocessed, other);
}

// Function Calls

device_selector = type:class_name _ attrlist:input_param_list {
    let id = null;
    let all = undefined;
    for (let { name, value } of attrlist) {
        if (name === 'id') {
            if (!value.isString)
                return error(`id attribute must be a constant string`);
            if (id)
                return error(`duplicate device id`);
            id = value.toJS();
        } else if (name === 'all') {
            if (!value.isBoolean)
                return error(`all attribute must be a constant boolean`);
            if (all !== undefined)
                return error(`duplicate device attribute all`);
            all = value.toJS();
        }
    }
    return new Ast.Selector.Device(location(), type, id, null,
        attrlist.filter((attr) => attr.name !== 'id' && attr.name !== 'all'), !!all);
}
device_attribute_list = first:device_attribute _ rest:(',' _ device_attribute _)* {
    return [first].concat(take(rest, 2));
}
device_attribute = name:('id' / 'name') _ '=' _ value:value {
    return new Ast.InputParam(location(), name, value);
}

short_function_name = '@' first_name:classident _ rest_names:('.' _ classident _)+ {
    let channel = rest_names[rest_names.length-1];
    rest_names.pop();

    let kind = first_name + (rest_names.length > 0 ? ('.' + take(rest_names, 2).join('.')) : '');
    return [new Ast.Selector.Device(location(), kind, null, null), channel[2]];
}
full_function_name = sel:device_selector _ '.' _ name:ident {
    return [sel, name];
}

input_param = name:qualified_name _ '=' _ value:value {
    return new Ast.InputParam(location(), name, value);
}
input_param_list = '(' _ ')' { return [] } / '(' _ first:input_param _ rest:(',' _ input_param _)* ')' {
    return [first].concat(take(rest, 2));
}

thingpedia_function_name = full_function_name / short_function_name
thingpedia_function_call = fn:thingpedia_function_name _ in_params:input_param_list {
    let [selector, function_name] = fn;
    return new Ast.Invocation(location(), selector, function_name, in_params, null);
}

// Tables and Streams

table_ref = name:ident _ in_params:input_param_list? {
  return new Ast.Table.VarRef(location(), name, in_params || [], null);
}
primary_table =
  call:thingpedia_function_call { return new Ast.Table.Invocation(location(), call, null); }
  / '(' _ table:table _ ')' { return table; }
  / 'result' _ '(' _ fn:short_function_name _ index:('[' _ value _ ']')? _ ')' {
    return new Ast.Table.ResultRef(location(), fn[0].kind, fn[1], index !== null ? index[2] : new Ast.Value.Number(-1), null);
  }
  / table_ref

sliced_table =
  table:primary_table _ '[' _ base:value _ ':' _ limit:value _ ']' { return new Ast.Table.Slice(location(), table, base, limit, null); } /
  table:primary_table _ '[' _ indices:array_value_list _ ']' { return new Ast.Table.Index(location(), table, indices, null); } /
  table:primary_table

primary_table_expression =
  table_projection / window_expression / history_expression
  / aggregate_expression / computed_table / sort_expression /
  sliced_table

table_projection = '[' _ first:qualified_name _ rest:(',' _ qualified_name _)* _ ']' _ 'of' __ table:alias_table {
  return new Ast.Table.Projection(location(), table, [first].concat(take(rest, 2)), null);
}
computed_table = 'compute' __ expr:value _ alias:('as' __ ident)? _ 'of' __ table:alias_table
{
    return new Ast.Table.Compute(location(), table, expr, alias !== null ? alias[2] : null, null);
}

window_expression = what:('window' / 'timeseries') _ '(' _ base:value _ ',' _ delta:value _ ')' _ 'of' __ stream:alias_stream {
  if (what === 'window')
    return new Ast.Table.Window(location(), base, delta, stream, null);
  else
    return new Ast.Table.TimeSeries(location(), base, delta, stream, null);
}
history_expression = what:('sequence' / 'history') _ '(' base:value _ ',' _ delta:value _ ')' _ 'of' __ table:alias_table {
  if (what === 'sequence')
    return new Ast.Table.Sequence(location(), base, delta, table, null);
  else
    return new Ast.Table.History(location(), base, delta, table, null);
}

aggregate_expression = 'aggregate' __ 'count' __ alias:('as' _ ident _)? 'of' __ table:alias_table {
  return new Ast.Table.Aggregation(location(), table, '*', 'count', alias !== null ? alias[2] : null, null);
} / 'aggregate' __ op:ident __ field:qualified_name _ alias:('as' _ ident _)? 'of' __ table:alias_table {
  return new Ast.Table.Aggregation(location(), table, field, op, alias !== null ? alias[2] : null, null);
}
sort_expression = 'sort' __ field:qualified_name _ direction:('asc' / 'desc') __ 'of' __ table:alias_table {
  return new Ast.Table.Sort(location(), table, field, direction, null);
}

alias_table = table:primary_table_expression _ alias:('as' __ ident)? {
  if (alias !== null)
    return new Ast.Table.Alias(location(), table, alias[2], null);
  else
    return table;
}

filtered_table = table:alias_table filter:(_ ',' _ or_expr)? {
  if (filter !== null)
    return new Ast.Table.Filter(location(), table, optimizeFilter(filter[3]), null);
  else
    return table;
}

table = first:filtered_table _ rest:('join' __ filtered_table _ ('on' _ input_param_list _ )?)* {
  return rest.reduce(((x, y) =>
      new Ast.Table.Join(location(), x, y[2], y[4] ? y[4][2]:[], null)), first);
}

stream_ref = name:ident _ in_params:input_param_list? {
  return new Ast.Stream.VarRef(location(), name, in_params || [], null);
}
primary_stream = timer / attimer / '(' _ stream:stream _ ')' { return stream; } / edge_trigger / monitor_stream / stream_projection / computed_stream / stream_ref

timer = 'timer' _ '(' _ 'base' _ '=' _ base:value _ ',' _ 'interval' _ '=' _ interval:value _ ')' {
    return new Ast.Stream.Timer(location(), base, interval, null, null);
} / 'timer' _ '(' _ 'base' _ '=' _ base:value _ ',' _ 'interval' _ '=' _ interval:value _ ',' _ 'frequency' _ '=' _ frequency:value _ ')' {
    return new Ast.Stream.Timer(location(), base, interval, frequency, null);
}

attimer = 'attimer' _ '(' _ 'time' _ '=' _ time:value _ ')' {
    if (time.isArray)
        return new Ast.Stream.AtTimer(location(), time.value, null, null);
    else
        return new Ast.Stream.AtTimer(location(), [time], null, null);
} / 'attimer' _ '(' _ 'time' _ '=' _ time:value _ ',' _ 'expiration_date' _ '=' _ expiration_date:(undefined_value / short_date_value) _ ')' {
    if (time.isArray)
        return new Ast.Stream.AtTimer(location(), time.value, expiration_date, null);
    else
        return new Ast.Stream.AtTimer(location(), [time], expiration_date, null);
}

edge_trigger = 'edge' __ stream:alias_stream _ 'on' __ edge:('new' !identchar / or_expr) {
  if (edge instanceof Ast.BooleanExpression)
    return new Ast.Stream.EdgeFilter(location(), stream, edge, null);
  else
    return new Ast.Stream.EdgeNew(location(), stream, null);
}

out_param_list = '[' _ first:qualified_name _ rest:(',' _ qualified_name _)* _ ']' {
  return [first].concat(take(rest, 2));
}

monitor_stream = 'monitor' __ table:alias_table _ params:('on' __ 'new' _ out_param_list)? {
  return new Ast.Stream.Monitor(location(), table, params !== null ? params[4] : null, null);
}

stream_projection = params:out_param_list _ 'of' __ stream:alias_stream {
  return new Ast.Stream.Projection(location(), stream, params, null);
}
computed_stream = 'compute' __ expr:value _ alias:('as' __ ident)? _ 'of' __ stream:alias_stream
{
    return new Ast.Stream.Compute(location(), stream, expr, alias !== null ? alias[2] : null, null);
}

alias_stream = stream:primary_stream _ alias:('as' __ ident)? {
  if (alias !== null)
    return new Ast.Stream.Alias(location(), stream, alias[2], null);
  else
    return stream;
}

filtered_stream = stream:alias_stream filter:(_ ',' _ or_expr)? {
  if (filter !== null)
    return new Ast.Stream.Filter(location(), stream, optimizeFilter(filter[3]), null);
  else
    return stream;
}

stream = first:filtered_stream _ rest:(('join' / '=>') __ filtered_table _ ('on' _ input_param_list _ )?)* {
  return rest.reduce(((x, y) => new Ast.Stream.Join(location(), x, y[2], y[4] ? y[4][2] : [], null)), first);
}

// Statements

top_level_statement = class_def / dataset / statement
statement = no_param_declaration / with_param_declaration / assignment / rule / on_input

lambda_param_decl_list = '(' _ ')' { return []; } /
    '(' _ first:lambda_param_decl _ rest:(',' _ lambda_param_decl _)* ')' {
    let ret = {};
    for (let [name, type] of [first, ...take(rest, 2)]) {
      ret[name] = type;
    }
    return ret;
}
lambda_param_decl = name:ident _ ':' _ type:type_ref {
    return [name, type];
}

no_param_declaration = 'let' __ 'stream' __ name:ident _ ':=' _ lambda:('\\' _ lambda_param_decl_list _ '->' _)? stream:stream _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'stream', lambda !== null ? lambda[2] : {}, stream, nl_annotations, impl_annotations, null);
} / 'let' __ ('table'/'query') __ name:ident _ ':=' _ lambda:('\\' _ lambda_param_decl_list _ '->' _)?  table:table _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'query', lambda !== null ? lambda[2] : {}, table, nl_annotations, impl_annotations, null);
} / 'let' __ 'action' __ name:ident _ ':=' _ lambda:('\\' _ lambda_param_decl_list _ '->' _)?  action:thingpedia_function_call _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'action', lambda !== null ? lambda[2] : {},
    new Ast.Action.Invocation(location(), action, null), nl_annotations, impl_annotations, null);
} / 'let' __ type:('program' / 'procedure') __ name:ident _ ':=' _ lambda:('\\' _ lambda_param_decl_list _ '->' _)? '{' _ statements:(statement _)+ '}' _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  const program = makeInput(take(statements, 0));
  return new Ast.Statement.Declaration(location(), name, type, lambda !== null ? lambda[2] : {}, program, nl_annotations, impl_annotations, null);
}

with_param_declaration = 'let' __ 'stream' __ name:ident _ lambda:lambda_param_decl_list _ ':=' _ stream:stream _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'stream', lambda, stream, nl_annotations, impl_annotations, null);
} / 'let' __ 'query' __ name:ident _ lambda:lambda_param_decl_list _ ':=' _ table:table _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'query', lambda, table, nl_annotations, impl_annotations, null);
} / 'let' __ 'action' __ name:ident _ lambda:lambda_param_decl_list _ ':=' _ action:thingpedia_function_call _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  return new Ast.Statement.Declaration(location(), name, 'action', lambda,
      new Ast.Action.Invocation(location(), action, null), nl_annotations, impl_annotations, null);
} / 'let' __ type:('program' / 'procedure') __ name:ident _ lambda:lambda_param_decl_list _ ':=' _ '{' _ statements:(statement _)+ '}' _ annotations:(_ annotation)* _ ';' {
  const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
  const program = makeInput(take(statements, 0));
  return new Ast.Statement.Declaration(location(), name, type, lambda, program, nl_annotations, impl_annotations, null);
}

assignment = 'let' __ 'result' __ name:ident _ ':=' _ table:table _ ';' {
  return new Ast.Statement.Assignment(location(), name, table);
}

action = fn:thingpedia_function_call {
  return new Ast.Action.Invocation(location(), fn, null);
} / builtin:('notify' / 'return') {
  return new Ast.Action.Invocation(location(), new Ast.Invocation(location(), Ast.Selector.Builtin, builtin, [], null), null);
} / name:ident _ in_params:input_param_list? {
  return new Ast.Action.VarRef(location(), name, in_params || [], null);
}

action_list = single:action { return [single]; }
  / '{' _ actions:(action _ ';' _)+ '}' {
  return take(actions, 0);
}
rule_body = 'now' __ '=>' _ table:table _ '=>' _ actions:action_list {
  return new Ast.Statement.Command(location(), table, actions);
} / 'now' __ '=>' _ actions:action_list {
  return new Ast.Statement.Command(location(), null, actions);
} / stream:filtered_stream _ tables:('=>' _ table _ ('on' _ input_param_list _ )? &('=>'))* '=>' _ actions:action_list {
  const streamJoin = tables.reduce((s, t) => new Ast.Stream.Join(location(), s, t[2], t[4] ? t[4][2] : [], null), stream);
  return new Ast.Statement.Rule(location(), streamJoin, actions);
} / stream:filtered_stream _ tables:('join' _ filtered_table _ ('on' _ input_param_list _ )?)* '=>' _ actions:action_list {
  const streamJoin = tables.reduce((s, t) => new Ast.Stream.Join(location(), s, t[2], t[4] ? t[4][2] : [], null), stream);
  return new Ast.Statement.Rule(location(), streamJoin, actions);
}
rule = body:rule_body _ ';' {
  return body;
}

on_input_choice = table:(table _ '=>' _)? actions:action_list _ annotations:(_ annotation)* _ ';' {
    const [nl_annotations, impl_annotations] = splitAnnotations(annotations);
    return new Ast.OnInputChoice(location(), table !== null ? table[0] : null, actions, nl_annotations, impl_annotations);
}

on_input = 'oninput' _ '=>' _ '{' _ choices:(on_input_choice _)+ _ '}' _ ';'? {
    const choicearray = take(choices, 0);
    choicearray.isOnInput = true;
    return choicearray;
}

// Boolean Expressions

get_predicate = fn:thingpedia_function_name _ in_params:input_param_list _ '{' _ filter:or_expr _ '}' {
    let [selector, function_name] = fn;
    return new Ast.BooleanExpression.External(location(), selector, function_name, in_params, filter, null);
}

macro_predicate = fname:thingpedia_function_name _ in_params:input_param_list {
    const [selector, name] = fname;
    return new Ast.BooleanExpression.VarRef(location(), selector, name, in_params);
}

function_style_predicate = fn:ident _ '(' _ lhs:qualified_name _ ',' _ rhs:value _ ')' !'(' {
    if (fn === 'substr')
        fn = '=~';
    return new Ast.BooleanExpression.Atom(location(), lhs, fn, rhs);
}

infix_predicate = lhs:qualified_name _ op:comparison_operator _ rhs:value {
    return new Ast.BooleanExpression.Atom(location(), lhs, op, rhs);
}

compute_predicate = lhs:value _ op:comparison_operator _ rhs:value {
    return new Ast.BooleanExpression.Compute(location(), lhs, op, rhs);
}

or_expr = first:and_expr rest:(_ '||' _ and_expr _)* {
    if (rest.length === 0)
        return first;
    return new Ast.BooleanExpression.Or(location(), [first].concat(take(rest, 3)));
}
and_expr = first:comp_expr rest:(_ '&&' _ comp_expr)* {
    if (rest.length === 0)
        return first;
    return new Ast.BooleanExpression.And(location(), [first].concat(take(rest, 3)));
}
comp_expr = infix_predicate / primary_bool_expr

primary_bool_expr = '(' _ or:or_expr _ ')' { return or; } /
    v:literal_bool { return v ? Ast.BooleanExpression.True : Ast.BooleanExpression.False; } /
    '!' _ bool:primary_bool_expr { return new Ast.BooleanExpression.Not(location(), bool); } /
    get_predicate / function_style_predicate / compute_predicate / macro_predicate

// Scalar Expressions

// Values (Primary Expressions)

date_value = absolute_date_value / edge_date_value / now

add_expr = first:mul_expr _ rest:(('+' / '-') _ mul_expr _)* {
  return rest.reduce(((x, y) => new Ast.Value.Computation(y[0], [x, y[2]])), first);
}
mul_expr = first:exp_expr _ rest:(('*' / '/' / '%') _ exp_expr _)* {
  return rest.reduce(((x, y) => new Ast.Value.Computation(y[0], [x, y[2]])), first);
}
exp_expr = first:array_field_value _ rest:('**' _ array_field_value _)* {
  return rest.reduce(((x, y) => new Ast.Value.Computation(y[0], [x, y[2]])), first);
}


value = add_expr

array_field_value = field:qualified_name _ 'of' __ value:filter_value {
    return new Ast.Value.ArrayField(value, field);
} / filter_value

filter_value = value:primary_value filter:(_ 'filter' _ '{' _ or_expr _ '}')? {
    if (filter !== null)
        return new Ast.Value.Filter(value, filter[5]);
    else
        return value;
}

scalar_function_args = '(' _ ')' { return []; } /
  '(' _ first:value _ rest:(',' _ value)* _ ')' {
  return [first].concat(take(rest, 2));
}

scalar_function = name:ident _ args:scalar_function_args {
  return new Ast.Value.Computation(name, args);
}

primary_value = '(' v:value ')' {
    return v;
} / constant_value /
    scalar_function /
    undefined_value /
    var_ref_value /
    context_value /
    event_value

constant_value =
        date_value /
        bool_value /
        measure_value /
        number_value /
        currency_value /
        time_value /
        location_value /
        enum_value /
        entity_value /
        string_value /
        array_value /
        arg_map_value /
        object_value

qualified_name = first:ident _ rest:('.' _ ident _)* {
  if (rest.length === 0)
    return first;
  else
    return first + '.' + take(rest, 2).join('.');
}
qualified_class_name = first:classident _ rest:('.' _ classident _)* {
  if (rest.length === 0)
    return first;
  else
    return first + '.' + take(rest, 2).join('.');
}

var_ref_value = name:qualified_name _ !'(' {
  return Ast.Value.VarRef(name);
}
undefined_value = '$undefined' remote:('.' _ 'remote')? {
    return Ast.Value.Undefined(remote === null);
} / '$?' {
    return Ast.Value.Undefined(true);
}

measure_value = num:literal_number unit:ident { return Ast.Value.Measure(num, unit); }
number_value = v:literal_number { return Ast.Value.Number(v); }
currency_value = ('makeCurrency' / 'new' __ 'Currency') _ '(' _ num:literal_number _ ',' _ code:ident _ ')' {
    return new Ast.Value.Currency(num, code);
}

long_date_value = ('makeDate' / 'new' __ 'Date') _ '(' _ year:literal_number _ ',' _ month:literal_number _ ',' _ day:literal_number _ ',' _ hours:literal_number _ ',' _ minutes:literal_number _ ',' _ seconds:literal_number _ ')' {
    var d = new Date;
    d.setFullYear(year);
    d.setMonth(month-1);
    d.setDate(day);
    d.setHours(hours);
    d.setMinutes(minutes);
    d.setSeconds(seconds);
    d.setMilliseconds(0);
    return new Ast.Value.Date(d);
}
short_date_value = ('makeDate' / 'new' __ 'Date') _ '(' _ year:literal_number _ ',' _ month:literal_number _ ',' _ day:literal_number _ ')' {
    var d = new Date;
    d.setFullYear(year);
    d.setMonth(month-1);
    d.setDate(day);
    d.setHours(0);
    d.setMinutes(0);
    d.setSeconds(0);
    d.setMilliseconds(0);
    return new Ast.Value.Date(d);
}
unix_date_value = ('makeDate' / 'new' __ 'Date') _ '(' _ unix:literal_number _ ')' {
    var d = new Date;
    d.setTime(unix);
    return new Ast.Value.Date(d);
}
iso_date_value = ('makeDate' / 'new' __ 'Date') _ '(' _ iso:literal_string _ ')' {
    return new Ast.Value.Date(new Date(iso));
}
absolute_date_value = long_date_value / short_date_value / unix_date_value / iso_date_value

time_unit = unit:ident {
    if (Units.normalizeUnit(unit) !== 'ms')
        error('Invalid time unit ' + unit);
    return unit;
}

edge_date_value = edge:('start_of' / 'end_of') _ '(' unit:time_unit _ ')' {
    if (unit === 'ms' || unit === 's')
        error(`${edge}(${unit}) is not allowed (not enough resolution)`);
    return new Ast.Value.Date(Ast.DateEdge(edge, unit));
}
now = ('makeDate' / 'new' __ 'Date') _ '(' _ ')' {
    return Ast.Value.Date(null);
}
time_value = ('makeTime' / 'new' __ 'Time') _ '(' hour:literal_number _ ',' _ minute:literal_number _ second:(',' _ literal_number _)? ')' {
    return Ast.Value.Time(Ast.Time.Absolute(hour, minute, second !== null ? second[2] : 0));
} / '$context' _ '.' _ 'time' _ '.' _ ctx:('morning' / 'evening') {
    return Ast.Value.Time(Ast.Time.Relative(ctx));
}
bool_value = v:literal_bool { return Ast.Value.Boolean(v); }
location_value = ('makeLocation' / 'new' __ 'Location') _ '(' _ lat:literal_number _ ',' _ lon:literal_number _ display:(',' _ literal_string _)?')' {
    return Ast.Value.Location(Ast.Location.Absolute(lat, lon, display !== null ? display[2] : null));
} / ('makeLocation' / 'new' __ 'Location') _ '(' _ name:literal_string _ ')' {
    return Ast.Value.Location(Ast.Location.Unresolved(name));
} / '$context' _ '.' _ 'location' _ '.' _ ctx:('home' / 'work' / 'current_location') {
    return Ast.Value.Location(Ast.Location.Relative(ctx));
}

context_value = '$context' _ '.' _ name:ident _ ':' _ type:type_ref _ {
    return new Ast.Value.ContextRef(name, type);
}

enum_value = 'enum' _ '(' _ v:ident _ ')' { return Ast.Value.Enum(v); }
string_value = v:literal_string { return Ast.Value.String(v);
}
event_value = '$event' _ evt:('.' _ ('type' / 'program_id'))? {
    return Ast.Value.Event(evt !== null ? evt[2] : null);
}

entity_type = '^^' _ prefix:qualified_class_name _ ':' _ entity:ident {
    return prefix + ':' + entity;
}

entity_value1 = v:literal_string _ type:entity_type _ display:('(' _ literal_string _')' _)? {
    return Ast.Value.Entity(v, type, display !== null ? display[2] : null);
}
entity_value2 = 'null' _ type:entity_type _ '(' _ display:literal_string _')' {
    return Ast.Value.Entity(null, type, display);
}
entity_value = entity_value1 / entity_value2

array_value = '[' _ values:array_value_list? _ ']' {
    return Ast.Value.Array(values || []);
}
array_value_list = first:value _ rest:(',' _ value _)* {
    return [first].concat(take(rest, 2));
}

arg_map_value = ('makeArgMap' / 'new' __ 'ArgMap') _ '(' _ first:( ident _ ':' _ type_ref ) _ rest:(',' _ ident _ ':' _ type_ref _ )* _ ')' {
    let map = {};
    map[first[0]] = first[4];
    if (rest.length !== 0)
        rest.forEach((r) => map[r[2]] = r[6]);
    return Ast.Value.ArgMap(map);
}

object_value = '{' _ first:( ident _ '=' _ value ) _ rest:(',' _ ident _ '=' _ value _ )* _ '}' {
    let obj = {};
    obj[first[0]] = first[4];
    if (rest.length !== 0)
        rest.forEach((r) => obj[r[2]] = r[6]);
    return Ast.Value.Object(obj);
}


annotation = nl_annotation / impl_annotation
nl_annotation = '#_[' name:ident _ '=' value:constant_value ']' {
    return { type: 'nl', name: name, value: value };
}
impl_annotation = '#[' name:ident _ '=' value:constant_value ']' {
    return { type: 'impl', name: name, value: value };
}

// Types

type_ref = 'Measure' _ '(' _ unit:ident? _ ')' { return Type.Measure(unit); } /
    'Enum' _ '(' _ first:ident _ rest:(',' _ ident _)* _ ')' { return Type.Enum([first].concat(take(rest, 2))); } /
    'Entity' _ '(' _ prefix:qualified_class_name _ ':' _ type:ident _ ')' { return Type.Entity(prefix + ':' + type); } /
    'Boolean' { return Type.Boolean; } /
    'String' { return Type.String; } /
    'Number' { return Type.Number; } /
    'Currency' { return Type.Currency; } /
    'Location' { return Type.Location; } /
    'Date' { return Type.Date; } /
    'Time' { return Type.Time; } /
    // for compat with Thingpedia
    'EmailAddress' { return Type.Entity('tt:email_address'); } /
    'PhoneNumber' { return Type.Entity('tt:phone_number'); } /
    'Picture' { return Type.Entity('tt:picture'); } /
    'Resource' { return Type.Entity('tt:rdf_resource'); } /
    'URL' { return Type.Entity('tt:url'); } /
    'Username' { return Type.Entity('tt:username'); } /
    'Hashtag' { return Type.Entity('tt:hashtag'); } /
    'Password' { return Type.Entity('tt:password'); } /
    'Type' { return Type.Type; } /
    'Array' _ '(' _ type:type_ref _ ')' { return Type.Array(type); } /
    'Any' { return Type.Any; } /
    '(' first:type_ref _ rest:(',' _ type_ref _)* ')' { return Type.Tuple([first].concat(take(rest, 2))); } /
    'ArgMap' { return Type.ArgMap; } /
    'Object' { return Type.Object; } /
    compound_type_ref /
    invalid:ident { return Type.Unknown(invalid); }

compound_type_ref = '{' _ first:compound_type_field _ rest:(',' _ compound_type_field _)* _ '}' {
    let fields = {};
    [first].concat(take(rest, 2)).forEach((arg) => {
        fields[arg.name] = arg;
    });
    return Type.Compound(null, fields);
}
compound_type_field = name:ident _ ':' _ type:type_ref annotations:( _ annotation _)* {
    const [nl, impl] = splitAnnotations(annotations);
    return new Ast.ArgumentDef(location(), undefined, name, type, { nl, impl });
}

// Tokens

comparison_operator "comparison operator" = '>=' / '<=' / '=~' / '~=' / '=='

literal_bool = 'true' !identchar { return true; } / 'false' !identchar { return false; }

// keywords which are not allowed as identifiers
keyword = literal_bool / ('let' / 'now' / 'new' / 'as' / 'of' / 'in' / 'out' / 'req' / 'opt' / 'notify' / 'return' / 'join' / 'edge' / 'monitor' / 'class' / 'extends' / 'mixin' / 'this' / 'import' / 'null' / 'enum' / 'aggregate' / 'dataset' / 'oninput' / 'sort' / 'asc' / 'desc' / 'bookkeeping' / 'compute' / 'filter') !identchar

// type names are also not allowed as identifiers
type_name = ('Measure' / 'Enum' / 'Entity' / 'Boolean' / 'String' / 'Number' / 'Currency' /
 'Location' / 'Date' / 'Time' / 'EmailAddress' / 'PhoneNumber' / 'Picture' / 'Resource' /
 'URL' / 'Username' / 'Hashtag' / 'Password' / 'Type' / 'Array' / 'Any' / 'ArgMap' / 'Object') !identchar

// dqstrchar = double quote string char
// sqstrchar = single quote string char
dqstrchar = [^\\\"] / "\\\"" { return '"'; } / "\\n" { return '\n'; } / "\\'" { return '\''; } / "\\\\" { return '\\'; }
sqstrchar = [^\\\'] / "\\\"" { return '"'; } / "\\n" { return '\n'; } / "\\'" { return '\''; } / "\\\\" { return '\\'; }
literal_string "string" = '"' chars:dqstrchar* '"' { return chars.join(''); }
    / "'" chars:sqstrchar* "'" { return chars.join(''); }
digit "digit" = [0-9]
literal_number "number" =
    num:$('-'? digit+ '.' digit* ('e' digit+)?) { return parseFloat(num); } /
    num:$('-'? '.' digit+ ('e' digit+)?) { return parseFloat(num); } /
    num:$('-'? digit+ ('e' digit+)?) { return parseFloat(num); }

identstart = [A-Za-z_]
identchar = [A-Za-z0-9_]
ident "identifier" = !(keyword / type_name) v:$(identstart identchar*) {
  // for debugging the prettyprinter
  if (v === 'undefined')
    throw new Error('Invalid undefined');
  return v;
}

classidentchar = [A-Za-z0-9_-]
classident "classidentifier" = !keyword v:$(identstart classidentchar*) { return v; }

// optional token separator
_ = (whitespace / comment)*
// required token separator (after keywords)
__ = (whitespace / comment)+ / !identchar

whitespace "whitespace" = [ \r\n\t\v]
comment "comment" = '/*' ([^*] / '*'[^/])* '*/' / '//' [^\n]* '\n'
