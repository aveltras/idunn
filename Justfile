build:
    cabal v2-build

clean:
    cabal v2-clean

compile-commands:
    bear -- clang++ -Wall -Wextra -std=c++20 -Icbits/include cbits/src/platform.cpp -o test_engine_build -fsyntax-only -Wno-unused-command-line-argument

run:
    MANGOHUD=1 cabal v2-run

watch:
    ghciwatch --command "cabal v2-repl --ghc-options='-fobject-code' --enable-multi-repl idunn demo" --watch src --watch demo
