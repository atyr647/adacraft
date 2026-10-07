GNATMAKE ?= gnatmake
SRC := -Igenerated -Isrc -Isrc/protocol -Isrc/kernel -Isrc/auth -Isrc/ingress -Isrc/network
FLAGS := -gnat2022 -gnata -D obj

.PHONY: all test server clean check check-packets-table

all: bin/adacraft bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state

bin/test_protocol_varnum: tests/test_protocol_varnum.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_varnum.adb -o $@

bin/test_protocol_state: tests/test_protocol_state.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_protocol_state.adb -o $@

bin/adacraft_tests: tests/adacraft_tests.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/adacraft_tests.adb -o $@

bin/test_ingress_framing: tests/test_ingress_framing.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) tests/test_ingress_framing.adb -o $@

bin/adacraft: src/adacraft_server.adb
	mkdir -p bin obj
	$(GNATMAKE) $(FLAGS) $(SRC) src/adacraft_server.adb -o $@

test: bin/adacraft_tests bin/test_ingress_framing bin/test_protocol_varnum bin/test_protocol_state
	$(MAKE) --no-print-directory check-packets-table
	$(MAKE) --no-print-directory check
	./bin/adacraft_tests
	./bin/test_ingress_framing
	./bin/test_protocol_varnum
	./bin/test_protocol_state

# Regenerates Adacraft.Protocol.Ids from the committed packets.json, compares
# it with the committed file, and checks the report SHA-256 recorded in the
# state spec. No network, no server.jar.
check-packets-table:
	mkdir -p obj
	sed 's|^OUT = .*|OUT = Path("obj/ids.regenerated.ads").resolve()|; s|OUT.relative_to(ROOT)|OUT.name|' tools/extract_reports.py > obj/extract_tmp.py
	sed -i 's|ROOT = Path(__file__).resolve().parents\[1\]|ROOT = Path("$(CURDIR)")|' obj/extract_tmp.py
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
