clean:
    cabal v2-clean

run:
    MANGOHUD=1 cabal v2-run

watch:
    ghciwatch --command "cabal v2-repl --ghc-options='-fobject-code' --enable-multi-repl idunn demo" --watch src --watch demo
