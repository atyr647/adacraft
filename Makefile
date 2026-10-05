GNATMAKE ?= gnatmake
SRC := -Igenerated -Isrc -Isrc/protocol -Isrc/kernel -Isrc/auth -Isrc/ingress -Isrc/network
FLAGS := -gnat2022 -gnata -D obj

.PHONY: all test server clean check

all: bin/adacraft bin/adacraft_tests bin/test_ingress_framing

bin/adacraft_tests: tests/adacraft_tests.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/adacraft_tests.adb -o $@

bin/test_ingress_framing: tests/test_ingress_framing.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_ingress_framing.adb -o $@

bin/adacraft: src/adacraft_server.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) src/adacraft_server.adb -o $@

test: bin/adacraft_tests bin/test_ingress_framing
	./bin/adacraft_tests
	./bin/test_ingress_framing

check:
	python3 tools/check_boundaries.py

server: bin/adacraft
	./bin/adacraft

clean:
	rm -rf obj bin
