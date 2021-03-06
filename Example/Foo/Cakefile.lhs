> {-# LANGUAGE QuasiQuotes, OverloadedStrings #-}


> module Cakefile where

Import the main Cake3 library. It imports Control.Monad plus some other
well-known modules.

> import Development.Cake3

Import paths and some location-dependent functions. This file is regenerated by the
cake3 script on each run.

> import Cakefile_P

Foo project incorporates a subproject (a library) which has it's own cakefile in
./lib/CakeLib.hs. We import it as usual haskell module. Thats why we should use
a different names for subprojects.

> import qualified CakeLib as L

A Makefile variable with default value

> cflags = makevar "CFLAGS" "-O0 -g3"

A Makefile variable set externally

> shellname = extvar "SHELL"

A usual haskell string

> greeting = "Yuupee"

Main project consists of only one file. Cake3 uses it's own representation of
files which is not a String. It makes quasy-quoters safer since we can see the
difference between files and plain Haskell strings.

> cfiles = [file "main.c"]

Declare a rule to build object files out of C sources. Each rule returns it's
set of targets, so we need a small wrapper to concatenate singleton lists.

Note the quasy quote syntax: $expr or $(expr) produce prerequisites of a rule
and @expr or @(expr) produce targets of a rule. Rules may have more than
one target. For example, shell [cmd| foo -o @o1 -o @o2 |] declares a command
producing both o1 and o2.

> rule_for_each l a = concat <$> forM l a
>
> os_local = rule_for_each cfiles $ \c -> rule $ do
>   shell [cmd| gcc -I lib -c $cflags -o @(c.="o") $c |]

This is how we can collect objects from main project and from a subproject it
includes.

> os = do
>   o1 <- os_local 
>   o2 <- L.os cflags
>   return (o1++o2)

Now we want to build the final executable. elf here has type Make [File] which
is safe to depend on.

> elf = rule $ do
>   shell [cmd| echo $(string greeting) |]
>   shell [cmd| echo SHELL is $shellname |]
>   shell [cmd| echo CFLAGS is $cflags |]
>   shell [cmd| gcc $cflags -o @(file "main.elf") $os |]

Main function of the Haskell program. We want to produce the Makefile containing
top-level target all. Also, we add selfUpdate rule which instructs make to
rebuild the Makefile if Cakefiles change.

Note that all will appear above clean since (all rule) is declared after the
(clean rule) in the Cakefile.

> main = writeMake (file "Makefile") $ do
>   rule $ do
>     phony "all"
>     depend elf
>   selfUpdate


