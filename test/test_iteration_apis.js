// -*- mode: js; indent-tabs-mode: nil; js-basic-offset: 4 -*-
//
// This file is part of Almond
//
// Copyright 2018 The Board of Trustees of the Leland Stanford Junior University
//
// Author: Giovanni Campagna <gcampagn@cs.stanford.edu>
//
// See COPYING for details
"use strict";

const assert = require('assert');

const Grammar = require('../lib/grammar_api');
const Ast = require('../lib/ast');
const SchemaRetriever = require('../lib/schema');
const Type = require('../lib/type');

const _mockSchemaDelegate = require('./mock_schema_delegate');
const schemaRetriever = new SchemaRetriever(_mockSchemaDelegate, null, true);

function assertArrayEquals(testCase, array, expected) {
    assert.strictEqual(array.length, expected.length);

    let failed = false;
    for (let i = 0; i < array.length; i++) {
        if (array[i] !== expected[i]) {
            console.error(`Test Case #${testCase+1}/${i+1}: does not match what expected`);
            console.error('Expected: ' + expected[i]);
            console.error('Generated: ' + array[i]);
            failed = true;
        }
    }
    if (failed)
        throw new Error(`testIterationAPIs ${testCase} FAILED`);
}

var TEST_CASES = [
    [`now => @com.xkcd.get_comic() => notify;`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'Builtin undefined:notify'],
    ['Selector(@com.xkcd)'],
     ],

    [`monitor (@com.xkcd.get_comic()) => notify;`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'Builtin undefined:notify'],
    ['Selector(@com.xkcd)'],
    ],

    [`monitor (@com.xkcd.get_comic(number=$undefined)) => notify;`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, InputParam(number, Undefined(true)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'InputParam(number, Undefined(true)) com.xkcd:get_comic',
     'Builtin undefined:notify'],
    ['Selector(@com.xkcd)',
     'InputParamSlot(number : Number) in_param.number What Xkcd comic do you want?'],
     ],

    [`monitor (@com.xkcd.get_comic(number=1234)) => notify;`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, InputParam(number, Number(1234)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'InputParam(number, Number(1234)) com.xkcd:get_comic',
     'Builtin undefined:notify'],
    ['Selector(@com.xkcd)',
     'InputParamSlot(number : Number) in_param.number What Xkcd comic do you want?'],
    ],

    [`monitor (@com.xkcd.get_comic(number=1234)) => @com.facebook.post(status=title);`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, InputParam(number, Number(1234)), )',
     'action: Invocation(Device(com.facebook, , ), post, InputParam(status, VarRef(title)), )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'InputParam(number, Number(1234)) com.xkcd:get_comic',
     'Device(com.facebook, , ) com.facebook:post',
     'InputParam(status, VarRef(title)) com.facebook:post'],
    ['Selector(@com.xkcd)',
     'InputParamSlot(number : Number) in_param.number What Xkcd comic do you want?',
     'Selector(@com.facebook)',
     'InputParamSlot(status : String) in_param.status What do you want to post?'],
     ],

    [`monitor (@com.xkcd.get_comic(number=1234)) => @com.facebook.post(status=$event);`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, InputParam(number, Number(1234)), )',
     'action: Invocation(Device(com.facebook, , ), post, InputParam(status, Event()), )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'InputParam(number, Number(1234)) com.xkcd:get_comic',
     'Device(com.facebook, , ) com.facebook:post',
     'InputParam(status, Event()) com.facebook:post'],
    ['Selector(@com.xkcd)',
     'InputParamSlot(number : Number) in_param.number What Xkcd comic do you want?',
     'Selector(@com.facebook)',
     'InputParamSlot(status : String) in_param.status What do you want to post?'],
    ],

    [`now => aggregate count of @com.xkcd.get_comic(number=1234) => @com.facebook.post(status=$event);`,
    ['query: Invocation(Device(com.xkcd, , ), get_comic, InputParam(number, Number(1234)), )',
     'action: Invocation(Device(com.facebook, , ), post, InputParam(status, Event()), )'],
    ['Device(com.xkcd, , ) com.xkcd:get_comic',
     'InputParam(number, Number(1234)) com.xkcd:get_comic',
     'Device(com.facebook, , ) com.facebook:post',
     'InputParam(status, Event()) com.facebook:post'],
    ['Selector(@com.xkcd)',
     'InputParamSlot(number : Number) in_param.number What Xkcd comic do you want?',
     'Selector(@com.facebook)',
     'InputParamSlot(status : String) in_param.status What do you want to post?'],
    ],

    [`now => aggregate avg temperature of (@com.instagram.get_pictures() join @org.thingpedia.weather.current() on (location=location)) => notify;`,
    ['query: Invocation(Device(com.instagram, , ), get_pictures, , )',
     'query: Invocation(Device(org.thingpedia.weather, , ), current, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.instagram, , ) com.instagram:get_pictures',
     'Device(org.thingpedia.weather, , ) org.thingpedia.weather:current',
     'Builtin undefined:notify'],
    ['Selector(@com.instagram)',
     'Selector(@org.thingpedia.weather)'],
    ],

    [`now => sort temperature asc of (@com.instagram.get_pictures() join @org.thingpedia.weather.current() on (location=location)) => notify;`,
    ['query: Invocation(Device(com.instagram, , ), get_pictures, , )',
     'query: Invocation(Device(org.thingpedia.weather, , ), current, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.instagram, , ) com.instagram:get_pictures',
     'Device(org.thingpedia.weather, , ) org.thingpedia.weather:current',
     'Builtin undefined:notify'],
    ['Selector(@com.instagram)',
     'Selector(@org.thingpedia.weather)'],
    ],

    [`now => (@com.instagram.get_pictures() join @org.thingpedia.weather.current() on (location=location))[1,2] => notify;`,
    ['query: Invocation(Device(com.instagram, , ), get_pictures, , )',
     'query: Invocation(Device(org.thingpedia.weather, , ), current, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.instagram, , ) com.instagram:get_pictures',
     'Device(org.thingpedia.weather, , ) org.thingpedia.weather:current',
     'Builtin undefined:notify'],
    ['Selector(@com.instagram)',
     'Selector(@org.thingpedia.weather)',
     'ArrayIndexSlot([0] : Number) table.index.0 What is the index of the first result you would like?',
     'ArrayIndexSlot([1] : Number) table.index.1 What is the index of the second result you would like?'],
    ],

    [`now => (@com.instagram.get_pictures() join @org.thingpedia.weather.current() on (location=location))[1:2] => notify;`,
    ['query: Invocation(Device(com.instagram, , ), get_pictures, , )',
     'query: Invocation(Device(org.thingpedia.weather, , ), current, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.instagram, , ) com.instagram:get_pictures',
     'Device(org.thingpedia.weather, , ) org.thingpedia.weather:current',
     'Builtin undefined:notify'],
    ['Selector(@com.instagram)',
     'Selector(@org.thingpedia.weather)',
     'FieldSlot(base : Number) slice.base What is the first result you would like?',
     'FieldSlot(limit : Number) slice.limit How many results would you like?'],
    ],

    [`monitor (@com.instagram.get_pictures() join @org.thingpedia.weather.current() on (location=location)) => notify;`,
    ['query: Invocation(Device(com.instagram, , ), get_pictures, , )',
     'query: Invocation(Device(org.thingpedia.weather, , ), current, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.instagram, , ) com.instagram:get_pictures',
     'Device(org.thingpedia.weather, , ) org.thingpedia.weather:current',
     'Builtin undefined:notify'],
    ['Selector(@com.instagram)',
     'Selector(@org.thingpedia.weather)'],
    ],

    [`(monitor @com.washingtonpost.get_article() join @com.yandex.translate.translate(target_language="zh"^^tt:iso_lang_code) on (text=title)) => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Undefined(true)), )',
     'query: Invocation(Device(com.yandex.translate, , ), translate, InputParam(target_language, Entity(zh, tt:iso_lang_code, )), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Undefined(true)) com.washingtonpost:get_article',
     'Device(com.yandex.translate, , ) com.yandex.translate:translate',
     'InputParam(target_language, Entity(zh, tt:iso_lang_code, )) com.yandex.translate:translate',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'Selector(@com.yandex.translate)',
     'InputParamSlot(target_language : Entity(tt:iso_lang_code)) in_param.target_language What\'s the target language? Use an ISO language code like it, en or zh.'],
    ],

    [`monitor @com.washingtonpost.get_article() join @com.yandex.translate.translate(target_language="zh"^^tt:iso_lang_code) on (text=title) => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Undefined(true)), )',
     'query: Invocation(Device(com.yandex.translate, , ), translate, InputParam(target_language, Entity(zh, tt:iso_lang_code, )), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Undefined(true)) com.washingtonpost:get_article',
     'Device(com.yandex.translate, , ) com.yandex.translate:translate',
     'InputParam(target_language, Entity(zh, tt:iso_lang_code, )) com.yandex.translate:translate',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'Selector(@com.yandex.translate)',
     'InputParamSlot(target_language : Entity(tt:iso_lang_code)) in_param.target_language What\'s the target language? Use an ISO language code like it, en or zh.'],
    ],

    [`monitor @com.washingtonpost.get_article(section=enum(world)) join @com.yandex.translate.translate(target_language="zh"^^tt:iso_lang_code) on (text=title) => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'query: Invocation(Device(com.yandex.translate, , ), translate, InputParam(target_language, Entity(zh, tt:iso_lang_code, )), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Device(com.yandex.translate, , ) com.yandex.translate:translate',
     'InputParam(target_language, Entity(zh, tt:iso_lang_code, )) com.yandex.translate:translate',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'Selector(@com.yandex.translate)',
     'InputParamSlot(target_language : Entity(tt:iso_lang_code)) in_param.target_language What\'s the target language? Use an ISO language code like it, en or zh.'],
    ],

    [`monitor @com.washingtonpost.get_article(section=enum(world)) => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?'],
    ],

    [`monitor @com.washingtonpost.get_article(section=enum(world)), title =~ "lol" => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Atom(title, =~, String(lol)) com.washingtonpost:get_article',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?'],
    ],

    [`monitor @com.washingtonpost.get_article(section=enum(world)), title =~ "lol" || title =~ "bar" => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Atom(title, =~, String(lol)) com.washingtonpost:get_article',
     'Atom(title, =~, String(bar)) com.washingtonpost:get_article',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?'],
    ],

    [`now => @com.washingtonpost.get_article(section=enum(world)), title =~ "lol" => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Atom(title, =~, String(lol)) com.washingtonpost:get_article',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?'],
    ],

    [`now => @com.washingtonpost.get_article(section=enum(world)), title =~ "lol" || title =~ "bar" => notify;`,
    ['query: Invocation(Device(com.washingtonpost, , ), get_article, InputParam(section, Enum(world)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.washingtonpost, , ) com.washingtonpost:get_article',
     'InputParam(section, Enum(world)) com.washingtonpost:get_article',
     'Atom(title, =~, String(lol)) com.washingtonpost:get_article',
     'Atom(title, =~, String(bar)) com.washingtonpost:get_article',
     'Builtin undefined:notify'],
    ['Selector(@com.washingtonpost)',
     'InputParamSlot(section : Enum(politics,opinions,local,sports,national,world,business,lifestyle)) in_param.section What section do you want to read?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?',
     'FilterSlot(title =~ : String) filter.=~.title What should the title contain?'],
    ],

    ['now => (@com.bing.web_search() join @com.yandex.translate.translate(target_language="it"^^tt:iso_lang_code("Italian")) on (text=$event)) => notify;',
    ['query: Invocation(Device(com.bing, , ), web_search, InputParam(query, Undefined(true)), )',
     'query: Invocation(Device(com.yandex.translate, , ), translate, InputParam(target_language, Entity(it, tt:iso_lang_code, Italian)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.bing, , ) com.bing:web_search',
     'InputParam(query, Undefined(true)) com.bing:web_search',
     'Device(com.yandex.translate, , ) com.yandex.translate:translate',
     'InputParam(target_language, Entity(it, tt:iso_lang_code, Italian)) com.yandex.translate:translate',
     'Builtin undefined:notify'],
    ['Selector(@com.bing)',
     'InputParamSlot(query : String) in_param.query What do you want to search?',
     'Selector(@com.yandex.translate)',
     'InputParamSlot(target_language : Entity(tt:iso_lang_code)) in_param.target_language What\'s the target language? Use an ISO language code like it, en or zh.'],
    ],

    ['monitor @com.bing.web_search() join @com.yandex.translate.translate(target_language="it"^^tt:iso_lang_code("Italian")) on (text=$event) => notify;',
    ['query: Invocation(Device(com.bing, , ), web_search, InputParam(query, Undefined(true)), )',
     'query: Invocation(Device(com.yandex.translate, , ), translate, InputParam(target_language, Entity(it, tt:iso_lang_code, Italian)), )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(com.bing, , ) com.bing:web_search',
     'InputParam(query, Undefined(true)) com.bing:web_search',
     'Device(com.yandex.translate, , ) com.yandex.translate:translate',
     'InputParam(target_language, Entity(it, tt:iso_lang_code, Italian)) com.yandex.translate:translate',
     'Builtin undefined:notify'],
    ['Selector(@com.bing)',
     'InputParamSlot(query : String) in_param.query What do you want to search?',
     'Selector(@com.yandex.translate)',
     'InputParamSlot(target_language : Entity(tt:iso_lang_code)) in_param.target_language What\'s the target language? Use an ISO language code like it, en or zh.'],
    ],

    ['dataset @com.twitter language \'en\' {\n' +
    '    stream (p_author : Entity(tt:username)) := monitor (@com.twitter.search()), author == p_author\n' +
    '    #_[utterances=[\'monitor ${p_author}\\\'s tweets\']];\n' +
    '    program := {\n' +
    '        monitor (@com.twitter.search()) => notify;\n' +
    '    }\n' +
    '    #_[utterances=[\'notify me about new tweets\']];\n' +
    '}',
    ['query: Invocation(Device(com.twitter, , ), search, , )',
     'query: Invocation(Device(com.twitter, , ), search, , )',
     'action: Invocation(Builtin, notify, , )'
    ],
    ['Device(com.twitter, , ) com.twitter:search',
     'Atom(author, ==, VarRef(p_author)) com.twitter:search',
     'Device(com.twitter, , ) com.twitter:search',
     'Builtin undefined:notify'
    ],
    ['Selector(@com.twitter)',
     'FilterSlot(author == : Entity(tt:username)) filter.==.author From which user do you want tweets?',
     'Selector(@com.twitter)'],
    ],

    [`let program p1(p_query : String) := {
        monitor (@com.bing.web_search(query=p_query)) => notify;
    };

    oninput => {
        // this should have a query=$? added
        p1();
    }`,
    ['action: VarRef(p1, InputParam(p_query, Undefined(true)), )'],
    ['InputParam(p_query, Undefined(true)) p1'],

    // FIXME typechecking of VarRef calls messes with the .schema in a way that
    // prevents us from knowing the correct slot type
    ['InputParamSlot(p_query : Any) in_param.p_query Please tell me the query.']
    ],

    [`now => result(@com.thecatapi.get) => notify;`,
    ['query: ResultRef(com.thecatapi, get, Number(-1), )',
     'action: Invocation(Builtin, notify, , )'],
     ['Builtin undefined:notify'],
    ['FieldSlot(index : Number) result_ref.index Which result do you want?']
    ],

    [`executor = $? : now => @com.twitter.post();`,

    [`action: Invocation(Device(com.twitter, , ), post, InputParam(status, Undefined(true)), )`],
    ['Device(com.twitter, , ) com.twitter:post',
     'InputParam(status, Undefined(true)) com.twitter:post'],
    ['FieldSlot(principal : Entity(tt:contact)) program.principal Who should run this command?',
     'Selector(@com.twitter)',
     'InputParamSlot(status : String) in_param.status What do you want to tweet?']
    ],

    [`attimer(time=$?) => @com.twitter.post();`,

    [`action: Invocation(Device(com.twitter, , ), post, InputParam(status, Undefined(true)), )`],
    ['Device(com.twitter, , ) com.twitter:post',
     'InputParam(status, Undefined(true)) com.twitter:post'],
    ['ArrayIndexSlot([0] : Time) attimer.time.0 When do you want your command to run?',
     'Selector(@com.twitter)',
     'InputParamSlot(status : String) in_param.status What do you want to tweet?']
    ],

    [`attimer(time=[$?, $?]) => @com.twitter.post();`,

    [`action: Invocation(Device(com.twitter, , ), post, InputParam(status, Undefined(true)), )`],
    ['Device(com.twitter, , ) com.twitter:post',
     'InputParam(status, Undefined(true)) com.twitter:post'],
    ['ArrayIndexSlot([0] : Time) attimer.time.0 What is the first time you would like your command to run?',
     'ArrayIndexSlot([1] : Time) attimer.time.1 What is the second time you would like your command to run?',
     'Selector(@com.twitter)',
     'InputParamSlot(status : String) in_param.status What do you want to tweet?']
    ],

    [`attimer(time=[$?, $?], expiration_date=$?) => @com.twitter.post();`,

    [`action: Invocation(Device(com.twitter, , ), post, InputParam(status, Undefined(true)), )`],
    ['Device(com.twitter, , ) com.twitter:post',
     'InputParam(status, Undefined(true)) com.twitter:post'],
    ['ArrayIndexSlot([0] : Time) attimer.time.0 What is the first time you would like your command to run?',
     'ArrayIndexSlot([1] : Time) attimer.time.1 What is the second time you would like your command to run?',
     'FieldSlot(expiration_date : Date) attimer.expiration_date When should your command stop?',
     'Selector(@com.twitter)',
     'InputParamSlot(status : String) in_param.status What do you want to tweet?']
    ],

    [`source == $? : now => @com.twitter.post;`,

    [],
    ['Atom(source, ==, Undefined(true))'],
    ['FilterSlot(source == : Entity(tt:contact)) filter.==.$source Who is allowed to ask you for this command?']
    ],

    [`in_array(source, $?) : now => @com.twitter.post;`,

    [],
    ['Atom(source, in_array, Undefined(true))'],
    ['FilterSlot(source in_array : Array(Entity(tt:contact))) filter.in_array.$source Who is allowed to ask you for this command?']
    ],

    [`in_array(source, [$?, $?]) : now => @com.twitter.post;`,

    [],
    ['Atom(source, in_array, Array(Undefined(true),Undefined(true)))'],
    ['FilterSlot(source in_array : Array(Entity(tt:contact))) filter.in_array.$source Who is allowed to ask you for this command?',
    'ArrayIndexSlot([0] : Entity(tt:contact)) filter.in_array.$source.0 Who is the first friend who is allowed to ask you for this command?',
    'ArrayIndexSlot([1] : Entity(tt:contact)) filter.in_array.$source.1 Who is the second friend who is allowed to ask you for this command?']
    ],

    [`now => @org.schema.restaurant(), count(review filter { author =~ "bob" }) >= 1 => notify;`,

    ['query: Invocation(Device(org.schema, , ), restaurant, , )',
     'action: Invocation(Builtin, notify, , )'],
    ['Device(org.schema, , ) org.schema:restaurant',
     'Builtin undefined:notify'],
    ['Selector(@org.schema)',
     'FieldSlot(lhs : Number) compute_filter.lhs What is the left hand side of the filter?',
     'FieldSlot(rhs : Number) compute_filter.rhs What is the right hand side of the filter?']
    ],

    [`now => @light-bulb(name="bedroom").set_power(power=enum(off));`,
    ['action: Invocation(Device(light-bulb, , ), set_power, InputParam(power, Enum(off)), )'],
    [
    'Device(light-bulb, , ) light-bulb:set_power',
    'InputParam(power, Enum(off)) light-bulb:set_power',
    ],
    [
    'DeviceAttributeSlot(name : String) attribute.name Please tell me the name of the device you would like to use.',
    'Selector(@light-bulb)',
    'InputParamSlot(power : Enum(on,off)) in_param.power Do you want to turn it on or off?',
    ]
    ]
];

async function test(i) {
    console.log('Test Case #' + (i+1));
    var [code, expectedPrim, expectedSlots, expectedSlots2] = TEST_CASES[i];

    try {
        const prog = await Grammar.parseAndTypecheck(code, schemaRetriever, true);
        const generatedSlots = Array.from(prog.iterateSlots()).map(([schema, slot, prim, scope]) => {
            if (!prim)
                return String(slot);
            else if (prim.isVarRef)
                return `${slot} ${prim.name}`;
            else
                return `${slot} ${prim.selector.kind}:${prim.channel}`;
        });
        const generatedSlots2 = Array.from(prog.iterateSlots2()).map((slot) => {
            if (slot instanceof Ast.Selector)
                return `Selector(@${slot.kind})`;

            assert(slot.type instanceof Type);
            assert(slot.get() instanceof Ast.Value);
            assert(Array.isArray(slot.options));
            return slot.toString() + ' ' + slot.tag + ' ' + slot.getPrompt('en-US');
        });
        const generatedPrims = Array.from(prog.iteratePrimitives(true)).map(([primType, prim]) => {
            prim.schema = null;
            return `${primType}: ${prim}`;
        });

        assertArrayEquals(i, generatedPrims, expectedPrim);
        assertArrayEquals(i, generatedSlots, expectedSlots);
        assertArrayEquals(i, generatedSlots2, expectedSlots2);
    } catch(e) {
        console.error('Test Case #' + (i+1) + ': failed with exception');
        console.error('Error: ' + e.message);
        console.error(e.stack);
        if (process.env.TEST_MODE)
            throw e;
    }
}

async function main() {
    for (let i = 0; i < TEST_CASES.length; i++)
        await test(i);
}
module.exports = main;
if (!module.parent)
    main();
