GNATMAKE ?= gnatmake
SRC := -Igenerated -Isrc -Isrc/protocol -Isrc/kernel -Isrc/auth -Isrc/ingress -Isrc/network
FLAGS := -gnat2022 -gnata -D obj

.PHONY: all test server clean check check-packets-table

all: bin/adacraft bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state bin/test_corpus_loader bin/test_golden_corpus bin/test_protocol_login bin/test_bad_clients bin/test_login_server bin/test_protocol_compression bin/test_handshake_exchange bin/test_status_exchange bin/test_protocol_packet_encoder

bin/test_protocol_varnum: tests/test_protocol_varnum.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_varnum.adb -o $@

bin/test_protocol_state: tests/test_protocol_state.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_state.adb -o $@

bin/test_protocol_login: tests/test_protocol_login.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_login.adb -o $@

bin/adacraft_tests: tests/adacraft_tests.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) -Itests $(SRC) tests/adacraft_tests.adb -o $@

bin/test_ingress_framing: tests/test_ingress_framing.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_ingress_framing.adb -o $@

bin/test_corpus_loader: tests/test_corpus_loader.adb tests/adacraft-corpus.ads tests/adacraft-corpus-loader.ads tests/adacraft-corpus-loader.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) -Itests $(SRC) tests/test_corpus_loader.adb -o $@

bin/test_golden_corpus: tests/test_golden_corpus.adb tests/adacraft-corpus.ads tests/adacraft-corpus-loader.ads tests/adacraft-corpus-loader.adb tests/adacraft-corpus-runner.ads tests/adacraft-corpus-runner.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) -Itests $(SRC) tests/test_golden_corpus.adb -o $@

bin/adacraft: src/adacraft_server.adb src/network/adacraft-network.adb src/network/adacraft-network.ads src/protocol/adacraft-protocol-login.adb src/protocol/adacraft-protocol-login.ads src/protocol/adacraft-protocol-frame.adb src/protocol/adacraft-protocol-frame.ads src/protocol/adacraft-protocol-varnum.adb src/protocol/adacraft-protocol-varnum.ads src/protocol/adacraft-protocol-handshake_exchange.adb src/protocol/adacraft-protocol-handshake_exchange.ads src/protocol/adacraft-protocol-state-table.adb src/protocol/adacraft-protocol-state-table.ads generated/adacraft-protocol-ids.ads
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) src/adacraft_server.adb -o $@

bin/test_bad_clients: tests/test_bad_clients.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_bad_clients.adb -o $@

bin/test_login_server: tests/test_login_server.adb bin/adacraft
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_login_server.adb -o $@

bin/test_protocol_compression: tests/test_protocol_compression.adb src/protocol/adacraft-protocol-zlib.ads src/protocol/adacraft-protocol-zlib.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_compression.adb -o $@ -largs -lz

bin/test_handshake_exchange: tests/test_handshake_exchange.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_handshake_exchange.adb -o $@

bin/test_status_exchange: tests/test_status_exchange.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_status_exchange.adb -o $@

bin/test_protocol_packet_encoder: tests/test_protocol_packet_encoder.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_packet_encoder.adb -o $@

test: bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state bin/test_corpus_loader bin/test_golden_corpus bin/test_protocol_login bin/test_bad_clients bin/test_login_server bin/test_protocol_compression bin/test_handshake_exchange bin/test_status_exchange bin/test_protocol_packet_encoder
	$(MAKE) --no-print-directory check-packets-table
	$(MAKE) --no-print-directory check
	./bin/adacraft_tests
	./bin/test_ingress_framing
	./bin/test_protocol_varnum
	./bin/test_protocol_state
	./bin/test_protocol_login
	./bin/test_corpus_loader
	./bin/test_golden_corpus
	./bin/test_bad_clients
	./bin/test_login_server
	./bin/test_protocol_compression
	./bin/test_handshake_exchange
	./bin/test_status_exchange
	./bin/test_protocol_packet_encoder

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

check:
	python3 tools/check_boundaries.py

server: bin/adacraft
	./bin/adacraft

clean:
	rm -rf obj bin
