build:
    cabal v2-build -- 1> debug.txt

clean:
    cabal v2-clean

check:
    pre-commit run -a

compile-commands:
    bear -- clang++ -Wall -Wextra -std=c++20 -Icbits/include cbits/src/*.cpp -o test_engine_build -fsyntax-only -Wno-unused-command-line-argument

run: build
    VK_LOADER_DEBUG=none MANGOHUD=1 cabal v2-run

watch:
    ghciwatch --command "cabal v2-repl --ghc-options='-fobject-code' --enable-multi-repl idunn demo" --watch src --watch demo
