# Command line arguments

## Command line arguments

Command line arguments can be specified in the GNU style, for example
`--foo=bar` or `--foo bar`, or `-f bar` when a short switch is
available. For more information, type {geni –help}.

## Options by theme

{sec:fancy\_parameters}

At the time of this writing (2009-09-25), it is highly unlikely that all
the options are documented here. See `geni --help` for more details.

Note that you might see an option described in more than one place
because it falls into multiple categories.

### Basic options

### Input files

See Chapter {cha:formats} for details on how to write these files.

macros
  ~ The `macros` switch is used to supply GenI with FB-LTAG tree
    schemata.

lexicon
  ~ The `lexicon` is used for lexical entries that point to the macros

suite
  ~ The `suite` provides test cases on which to run GenI

ranking
  ~ The `ranking` switch allows you to specify a file containing
    Optimality Theory style constraints which GenI will use to rank its
    output. See Chapter {cha:ranking} for more details on the format and
    use of this file.

### Output

### User interface

### Optimisations

opt
  ~ The opt switch lets you specify a list of optimisations that GenI
    should use, for example, `--opt='pol S i'`. We associate each
    optimisation with a short code like ’i’ for “index accessibility
    filtering”. This code is what the user passes in, and is sometimes
    used by GenI to tell the user which optimisations it’s using. See
    {geni –help} for more detail on the codes.

    Optimisations can be accumulated. For example, if you say something
    like `--opt='foo bar' --opt='quux'` it is the same as saying
    `--opt='foo bar quux'`.

    Note that we also have two special thematic codes “pol” and “adj”
    which tell GenI that it should enable all the polarity-related, and
    all the adjunction-related optimisations respectively.

detect-pols
  ~ This tells GenI how to detect polarities in your grammar. You pass
    this in in the form of a space-delimited string, where each word is
    either an attribute or a “restricted” attribute. In lieu of an
    explanation, here is an example: the string “cat idx V.tense D.c”
    tells GenI that we should detect polarities on the “cat” and “idx”
    attribute for all nodes and also on the “tense” attribute for all
    nodes with the category “V” and the “c” attribute for all nodes with
    the category “D”.

    If your grammar comes with its own hand-written polarities, you can
    suppress polarity detection altogether by supplying the empty
    string.

    Also, if you do not use this switch, the following defaults will be
    used:

rootfeat
  ~ No results? Make sure your rootfeat are set correctly. GenI will
    reject all sentences whose root category does not unify with the
    rootfeat. A possible default root feature might be

    By the default the root feature allows pretty much any result
    through, but for best results, you should probably constrain it a
    little more. Note that an empty root feature is also legal, but
    would cause polarity filtering to filter the wrong things.

### Builders

builder
  ~ A builder is basically a surface realisation algorithm. has the
    infrastructure to support different realisation algorithms, but some
    broken ones have been removed.

### Testing and profiling

### Morphology

GenI provides two options for morphology: either you use an external
inflection program (morphcmd), or you pass in a morphological lexicon
(morphlexicon) and in doing so, use GenI’s built in inflecter. The GenI
internal morphology mechanism is a simple and stupid lookup-and- unify
table, so you probably don’t want to use it if you have a huge lexicon.

morphcmd
  ~ specifies the program used for morphology. Literate GenI has a
    chapter describing how that program must work. It will mostly likely
    be a script you wrote to wrap around some off-the-shelf software.

morphlexicon
  ~ specifies a morphological lexicon for use by GenI’s internal
    morphological generator. Specifying this option will cause the
    morphcmd flag to be ignored.

morphinfo
  ~ tells GenI which literals in the input semantics are to be used by
    the morphological *pre-*processor. The pre-processor strips these
    features from the input and fiddles with the elementary trees used
    by GenI so that the right features get attached to the leaf nodes.
    An example of a “morphological” literal is something like `past(p)`.

## Scripting GenI

instructions
  ~ An instructions file can be used to run GenI on a list of test
    suites and cases.

    Any input that you give to GenI will be interpreted as a list of
    test suites (and test cases that you want to run). Each line has the
    format `path/to/test-suite case1 case2 .. caseN`. You can omit the
    test cases, which is interpreted as you wanting to run the entire
    test suite. Also, the `%` character and anything after is treated as
    a comment.

    Interaction with `--testsuite` and `--testcase`:

    -   If only `--instructions` is set, then the first test suite and
        or test case from the instructions file is used.

    -   If only `--testsuite` and `--testcase` are set, we pretend that
        an instructions file was supplied saying that we want to run the
        entirety of the test suite specified in `--testsuite`.

    -   If both `--instructions` and `--testsuite`/ `--testcase` are set
        then the latter are used to select from within the instructions.

## Configuration file
