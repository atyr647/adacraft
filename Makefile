GNATMAKE ?= gnatmake
SRC := -Igenerated -Isrc -Isrc/protocol -Isrc/kernel -Isrc/auth -Isrc/ingress -Isrc/network -Isrc/crypto
FLAGS := -gnat2022 -gnata -D obj
LARGS := -largs -lcrypto

.PHONY: all test server clean check check-packets-table

all: bin/adacraft bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state bin/test_corpus_loader bin/test_golden_corpus bin/test_protocol_login_encryption

bin/test_protocol_varnum: tests/test_protocol_varnum.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_varnum.adb -o $@ $(LARGS)

bin/test_protocol_login_encryption:
	mkdir -p bin obj
	if [ -f tests/test_protocol_login_encryption.adb ]; then \
	  $(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_login_encryption.adb -o $@ $(LARGS); \
	else \
	  echo "skip $@ (tests/test_protocol_login_encryption.adb not present)"; \
	fi

bin/test_protocol_state: tests/test_protocol_state.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_state.adb -o $@ $(LARGS)

bin/adacraft_tests: tests/adacraft_tests.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/adacraft_tests.adb -o $@ $(LARGS)

bin/test_ingress_framing: tests/test_ingress_framing.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_ingress_framing.adb -o $@ $(LARGS)

bin/test_corpus_loader: tests/test_corpus_loader.adb tests/adacraft-corpus.ads tests/adacraft-corpus-loader.ads tests/adacraft-corpus-loader.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) -Itests $(SRC) tests/test_corpus_loader.adb -o $@ $(LARGS)

bin/test_golden_corpus: tests/test_golden_corpus.adb tests/adacraft-corpus.ads tests/adacraft-corpus-loader.ads tests/adacraft-corpus-loader.adb tests/adacraft-corpus-runner.ads tests/adacraft-corpus-runner.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) -Itests $(SRC) tests/test_golden_corpus.adb -o $@ $(LARGS)

bin/adacraft: src/adacraft_server.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) src/adacraft_server.adb -o $@ $(LARGS)

test: bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state bin/test_corpus_loader bin/test_golden_corpus bin/test_protocol_login_encryption
	$(MAKE) --no-print-directory check-packets-table
	$(MAKE) --no-print-directory check
	./bin/adacraft_tests
	./bin/test_ingress_framing
	./bin/test_protocol_varnum
	./bin/test_protocol_state
	./bin/test_corpus_loader
	./bin/test_golden_corpus
	if [ -x bin/test_protocol_login_encryption ]; then ./bin/test_protocol_login_encryption; else echo "skip test_protocol_login_encryption (not present)"; fi

# Regenerates Adacraft.Protocol.Ids from the committed packets.json, compares
# it with the committed file, and checks the report SHA-256 recorded in the
# state spec. No network, no server.jar.
check-packets-table:
	mkdir -p obj
	sed -e 's|^OUT = .*|OUT = Path("obj/ids.regenerated.ads").resolve()|' -e 's|OUT.relative_to(ROOT)|OUT.name|' -e 's|^ROOT = .*|ROOT = Path("$(CURDIR)")|' tools/extract_reports.py > obj/extract_tmp.py
	python3 obj/extract_tmp.py > /dev/null
	cmp obj/ids.regenerated.ads generated/adacraft-protocol-ids.ads || { echo "generated Ids differ from packets.json"; exit 1; }
	h=$$(python3 -c "import hashlib;print(hashlib.sha256(open('generated/26.3/reports/packets.json','rb').read()).hexdigest())"); \
	grep -q "\"$$h\"" src/protocol/adacraft-protocol-state.ads || { echo "Report_SHA256 does not match packets.json ($$h)"; exit 1; }
	j=$$(sed -n 's/^server_jar_sha256 = "\(.*\)"/\1/p' pin/26.3.toml); \
	grep -q "\"$$j\"" src/protocol/adacraft-protocol-state.ads || { echo "Server_Jar_SHA256 does not match pin"; exit 1; }; \
	grep -q "$$j" generated/26.3/PROVENANCE.md || { echo "PROVENANCE.md does not match pin"; exit 1; }
	@echo "packets table ok"

bin/test_protocol_packet_decoder: tests/test_protocol_packet_decoder.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_packet_decoder.adb -o $@ $(LARGS)

bin/test_protocol_packet_encoder: tests/test_protocol_packet_encoder.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_packet_encoder.adb -o $@ $(LARGS)

check: bin/test_protocol_packet_decoder
	python3 tools/check_boundaries.py && echo test_protocol_packet_decoder && ./bin/test_protocol_packet_decoder

server: bin/adacraft
	./bin/adacraft

clean:
	rm -rf obj bin
# glue: src/crypto + -lcrypto + login-encryption driver (no crypto logic here)
