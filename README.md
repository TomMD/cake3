Cake3
=====

Cake3 is a EDSL for building Makefiles, written in Haskell. With cake3,
developer can write their build logic in Haskell, obtain clean and safe Makefile
and distribute it among the non-Haskell-aware users. Currenly, GNU Make is
the only backend supported.

The Goals
---------

Make is a build tool which was created more than 20 yesrs ago. It has a number
of versions and dialects. Basic Makefiles are really easy to write and
understand.  Unfortunately, it is hard to write real-world scale set of rules
correctly due to tricky syntax and lots of pitfails. As of today, Make has
automatic, declarative and imperative variables, builtin rules, pattern-rules,
double-colon rules, C-style ifdefs (which doesn't work well with declarative
variables) and lots of other strange things. Nevertheless, it is still widely
used as a de-facto standard tool which everyone has access to.

The goals of Cake3 are to help the developer to:

  * Stop overusing Make by writing complex logic in make-language
  * Still have a correct Makefile which could be distributed among the users
  * Take a bit of Haskell practice :)

Installation
------------

From Hackage:
  
    $ cabal install cake3


From the Github:

  1. Install [Haskell Platform](http://www.haskell.org/platform/)

  2. Install dependencies
    
         $ cabal install haskell-src-meta monadloc QuasiText

  3. Build the thirdcake from Github

         $ git clone http://github.com/grwlf/cake3
         $ cd cake3
         $ cabal configure && cabal install

Usage
-----

  1. Create the Cakefile.hs in the root dir of your project

        $ cake3 init

  2. Edit Cakefile.hs, fill it with rules or other logic you need 

        $ vim Cakefile.hs

  3. Debug your generator with

        $ cake3 ghci
        Prelude> :lo Cakefile.hs 

  3. Build the Makefile with cake3

        $ cake3

  4. Run GNU make as usual

How does it work
----------------

Cake3 allows user to write Cakefile.hs in plain Haskell to define rules, targets
and other stuff as usual. After that, `cake3` compiles it into ./Cakegen
application which builds your Makefile (ghc is required for that). GNU Make
knows how to do the rest.

### Example

Here is the example of simple Cakefile.hs:

    {-# LANGUAGE QuasiQuotes, OverloadedStrings #-}
    module Cakefile where

    import Development.Cake3
    import Development.Cake3.Utils.Find
    import Cakefile_P

    main = writeMake "Makefile" $ do

      cs <- filterDirectoryContentsRecursive [".c"]

      d <- rule $ do
        shell [cmd|gcc -M @cs -MF %(file "depend.mk")|]

      os <- forM cs $ \c -> do
        rule $ do
          shell [cmd| gcc -c $(extvar "CFLAGS") -o %(c.="o") @c |]

      elf <- rule $ do
        shell [cmd| gcc -o %(file "main.elf") @os |]

      b <- rule $ do
        phony "all"
        depend elf

      includeMakefile d

### Explanation

  * Quasy-quotation `[cmd||]`


Features and limitations
------------------------

Thirdcake follows Autoconf's path in a sence that it generates Makefile which
can be used with current and modified (up to some level) environment but has to
be regenerated when environment modifications exceeds that level.

Currently, the tool doesn't support pattern rules and variable-level functions
so nearly all the computatinos should be done at Haskell level. However, as a
reward, thirdcake protect the develper from a number of common make-specific
mistakes.

### Features

  * *Spaces inside the filenames*
  
    Everyone knows that Makefiles don't like spaces. Actually, the '\ '
    syntax is the only way to deal with them.

  * *Rebuild a rule when variable changes.*
  
    Consider following antipattern:

        # You often write rules like this, don't you?
        out : in
             foo $(FLAGS) -o $@ $^

    Unfortunately, changes in FLAGS don't lead to rebuilding of out.
    Hardly-trackable bugs may appear if one part of a project was built with one
    set of optimisation flags and another part was build with another set by
    mistake.

    Thirdcake implements the makevar checksum
    [pattern](http://stackoverflow.com/a/17830736/1133157) from StackOverflow to
    detect changes in variables and rebuild targets when nessesary.
 
  * *A rule with multiple targets.*
    
    It is not that simple to write a rule which has more than one target. Really,
        
        out1 out2 : in1 in2
            foo in1 in2 -o1 out1 -o2 out2

    is not corret. Read this [Automake
    article](http://www.gnu.org/software/automake/manual/html_node/Multiple-Outputs.html#Multiple-Outputs)
    if you are surprised. Thirdcake implements [.INTERMEDIATE
    pattern](http://stackoverflow.com/a/10609434/1133157) to deal with this
    problem

  * *Makefiles hierarchy.*
  
    Say, we have a project A with subproject L. L has it's own Makefile and we
    want to re-use it from our global A/Makefile. Make provides only two ways of
    doing that. We could either include L/Makefile or call $(MAKE) -C L. First
    solution is a pain because merging two Makefiles together is generally a
    hard work. Second approach is OK, but only if we don't need to pass
    additional paramters or depend on a specific rule from L.

    Thirdcake's approach in this case is a compromise: it employs Haskell's
    import mechanism so it is possible to import L/Cakefile.hs from
    A/Cakefile.hs and do whatever you want to. Resulting makefiles will always
    be monolitic.

### Limitations

  * Resulting Makefile is actually a GNUMakefile. GNU extensions (shell function
    and others) are needed to make variable-guard tricks to work.
  * Coreutils package is required because resulting Makefile calls md5sum and
    cut programs.
  * All Cakefiles across the project tree should have unique names in order to
    be copied. Duplicates are found, the first one is used
  * Posix environment is required. So, Linux, Probably Mac, Probably
    Windows+Cygwin.
  * Wildcards are not supported in the output Makefile language subset. I plan
    to experiment with supporting them, but think that space problem will
    probably arise.
  * Variables-as-targets are also not supported.

Random implementation details
-----------------------------

  1. User writes a cakefile (./Cake\*.hs) describing the rules. Refer to
     Example/GHC/Cakefile.hs. Note, that different cakefiles should have
     different names even if they are in different directories due to GHC import
     restrictions. This way user can import one cakefile from another, as if
     they were in the same directory. Actually, cake3 copies all cakefiles into
     one temporary directory and compiles them there.

  2. Cake3 copies all Cake\*.hs files from your project tree into temporary dir
     and compiles them with GHC (or calls GHCi). Before that, it creates a
     ./Cake\*_P.hs pathfile containing information about paths. The most
     important is _files_ function which translates relative _filename_ into
     _"." </> path_to_subproject </> filename_.

  3. Cake3 uses relative paths only for the final Makefile

