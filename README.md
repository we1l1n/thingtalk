# ThingTalk

[![Build Status](https://travis-ci.org/stanford-oval/thingtalk.svg?branch=master)](https://travis-ci.org/stanford-oval/thingtalk) [![Coverage Status](https://coveralls.io/repos/github/stanford-oval/thingtalk/badge.svg?branch=master)](https://coveralls.io/github/stanford-oval/thingtalk?branch=master) [![Dependency Status](https://david-dm.org/stanford-oval/thingtalk/status.svg)](https://david-dm.org/stanford-oval/thingtalk) [![Greenkeeper badge](https://badges.greenkeeper.io/stanford-oval/thingtalk.svg)](https://greenkeeper.io/) [![Language grade: JavaScript](https://img.shields.io/lgtm/grade/javascript/g/stanford-oval/thingtalk.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/stanford-oval/thingtalk/context:javascript)

## The Programming Language of Virtual Assistants

ThingTalk is the declarative (rule-based) distributed programming
language for virtual assistants. It connects to multiple web services
and IoT devices in a single _when-get-do_ statement.

For example, in ThingTalk you can say:
```
monitor (@com.washingtonpost.get_article(section=enum(world))) => @com.yandex.translate.translate(target_language="zh"^^tt:iso_lang_code) on (text=title) =>
@com.facebook.post(status=$event);
```

This program automatically monitors Washington Post headlines, translates them to Chinese, and then posts them on Facebook.
It does so by referring to primitives defined in [Thingpedia](https://thingpedia.stanford.edu), an open-source crowdsourced repository of APIs and metadata.

ThingTalk the language component of the Almond virtual assistant.
You can find a guide to the ThingTalk language on the [Almond website](https://almond.stanford.edu/thingpedia/developers/thingtalk-intro.md).

This package contains the grammar, the compiler of the language,
the interface to analyze programs using SMT, the code to translate
from ThingTalk to natural language, part of the ThingTalk runtime,
and various libraries to manipulate ThingTalk ASTs.

While this library is useful on its own for specific purposes, to
run ThingTalk programs you will need a full Almond runtime, such
as one provided by [almond-cloud](https://github.com/stanford-oval/almond-cloud)
or [almond-cmdline](https://github.com/stanford-oval/almond-cmdline).

Almond is a research project led by prof. Monica Lam,
from Stanford University.  You can find more information at
<https://almond.stanford.edu>

## License

This package is covered by the GNU General Public License, version 3
or any later version. See [LICENSE](LICENSE) for details.

## Versioning

This package **does not** follow semantic versioning. Instead, the version should
be interpreted as:

- Major version will be bumped for incompatible changes in the language, such that
  existing valid programs are no longer valid
- Minor version will be bumped for any change in the library, such as AST definitions,
  interfaces to compilation/optimization passes, adding and removing additional processing
  modules
- Patch version will be bumped for compatible bug fixes

**Minor version bumps can introduce incompatibility to library users**; it is
recommended that library users use tilde version ranges on their ThingTalk dependency,
or use a service such as [Greenkeeper](https://greenkeeper.io) to check for incompatibilities
when a new version of the ThingTalk library is published.
