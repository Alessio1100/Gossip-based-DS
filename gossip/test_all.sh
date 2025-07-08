#!/bin/bash
# test_complete.sh - Suite completa di test per sistema Gossip

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${PURPLE}🧪 SUITE COMPLETA TEST SISTEMA GOSSIP 🧪${NC}"
echo "=================================================="

# Funzioni utility
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_test() { echo -e "${CYAN}🧪 $1${NC}"; }

wait_seconds() {
    local seconds=$1
    local message=$2
    echo -e "${YELLOW}$message${NC}"
    for ((i=$seconds; i>=1; i--)); do
        printf "\r⏳ Attendi %d secondi..." $i
        sleep 1
    done
    echo -e "\r✅ Completato!          "
}

print_separator() {
    echo -e "${CYAN}========================================${NC}"
}

# Variabili globali per tracking risultati
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()
TOTAL_START_TIME=$(date +%s)

record_test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [ "$result" = "PASS" ]; then
        ((TESTS_PASSED++))
        TEST_RESULTS+=("✅ $test_name: PASSATO - $details")
    else
        ((TESTS_FAILED++))
        TEST_RESULTS+=("❌ $test_name: FALLITO - $details")
    fi
}

# Cleanup iniziale
log_info "Cleanup iniziale completo..."
docker-compose down -v &>/dev/null 2>&1 || true
sleep 3

echo ""
echo "📋 PIANO DI TEST:"
echo "1. 🚀 JOIN: Aggiunta progressiva di nodi (2-5 nodi)"
echo "2. 🚪 LEAVE: Uscita graceful con propagazione"
echo "3. 💀 FAILURE: Morte improvvisa + detection completa"
echo "4. 🧟 RESURRECTION: Recovery di nodo morto"
echo "5. 🔄 STRESS: Operazioni multiple simultanee"
echo ""
read -p "Continuare con tutti i test? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Test cancellato dall'utente."
    exit 0
fi

# =================================================================
# TEST 1: JOIN PROGRESSIVO
# =================================================================
print_separator
log_test "TEST 1: JOIN PROGRESSIVO"
print_separator

TEST1_START=$(date +%s)
log_info "Avvio nodo bootstrap (node1)..."
docker-compose up -d node1
wait_seconds 10 "Stabilizzazione nodo bootstrap..."

# Verifica bootstrap
BOOTSTRAP_OK=$(docker-compose logs node1 --tail=20 2>/dev/null | grep "BOOTSTRAP.*inizializzato" | wc -l)
if [ "$BOOTSTRAP_OK" -gt 0 ]; then
    log_success "Nodo bootstrap inizializzato correttamente"
else
    log_error "Problema con nodo bootstrap"
    record_test_result "JOIN_PROGRESSIVO" "FAIL" "Bootstrap fallito"
    exit 1
fi

# JOIN progressivo
NODES_TO_ADD=("node2" "node3" "node4" "node5")
CURRENT_COUNT=1
JOIN_SUCCESS=true

for node in "${NODES_TO_ADD[@]}"; do
    log_info "JOIN di $node (${CURRENT_COUNT}/5 → $((CURRENT_COUNT+1))/5)..."
    docker-compose up -d $node

    wait_seconds 15 "Attesa propagazione JOIN..."

    ((CURRENT_COUNT++))
    ACTUAL_COUNT=$(docker-compose logs --tail=30 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

    if [ "$ACTUAL_COUNT" -eq "$CURRENT_COUNT" ]; then
        log_success "$node joinato: $ACTUAL_COUNT/$CURRENT_COUNT nodi"
    else
        log_warning "$node JOIN incompleto: $ACTUAL_COUNT/$CURRENT_COUNT nodi"
        # Tolleranza: aspetta altri 10s
        wait_seconds 10 "Attesa extra propagazione..."
        ACTUAL_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")
        if [ "$ACTUAL_COUNT" -eq "$CURRENT_COUNT" ]; then
            log_success "$node joinato dopo attesa extra: $ACTUAL_COUNT nodi"
        else
            log_error "$node JOIN fallito definitivamente: $ACTUAL_COUNT/$CURRENT_COUNT nodi"
            JOIN_SUCCESS=false
        fi
    fi
done

TEST1_END=$(date +%s)
TEST1_DURATION=$((TEST1_END - TEST1_START))

if [ "$JOIN_SUCCESS" = true ]; then
    record_test_result "JOIN_PROGRESSIVO" "PASS" "5 nodi, ${TEST1_DURATION}s"
    log_success "JOIN PROGRESSIVO completato in ${TEST1_DURATION}s"
else
    record_test_result "JOIN_PROGRESSIVO" "FAIL" "Alcuni JOIN falliti"
    log_error "JOIN PROGRESSIVO fallito"
fi

# Pausa inter-test
wait_seconds 10 "Pausa stabilizzazione inter-test..."

# =================================================================
# TEST 2: LEAVE GRACEFUL
# =================================================================
print_separator
log_test "TEST 2: LEAVE GRACEFUL"
print_separator

TEST2_START=$(date +%s)
LEAVE_NODE="node3"
EXPECTED_AFTER_LEAVE=4

log_info "Stato pre-LEAVE:"
PRE_LEAVE_COUNT=$(docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")
log_info "Nodi attivi: $PRE_LEAVE_COUNT"

log_info "Esecuzione LEAVE graceful di $LEAVE_NODE..."

# Capture logs in background
timeout 8s docker-compose logs -f $LEAVE_NODE 2>/dev/null | grep -E "(EXIT|LEAVE)" &
LEAVE_LOG_PID=$!

# Graceful stop
docker-compose stop $LEAVE_NODE

wait_seconds 8 "Attesa elaborazione LEAVE messages..."

# Kill background log capture
kill $LEAVE_LOG_PID 2>/dev/null || true

# Verifica LEAVE
LEAVE_SENT=$(docker-compose logs $LEAVE_NODE 2>/dev/null | grep "LEAVE.*Messaggio LEAVE inviato" | wc -l)
LEAVE_RECEIVED=$(docker-compose logs 2>/dev/null | grep "LEAVE.*Ricevuto messaggio LEAVE da.*$LEAVE_NODE" | wc -l)

wait_seconds 15 "Attesa propagazione via gossip..."

POST_LEAVE_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

TEST2_END=$(date +%s)
TEST2_DURATION=$((TEST2_END - TEST2_START))

LEAVE_SUCCESS=true
if [ "$LEAVE_SENT" -eq 0 ]; then
    log_error "LEAVE messages non inviati"
    LEAVE_SUCCESS=false
fi

if [ "$LEAVE_RECEIVED" -eq 0 ]; then
    log_error "LEAVE messages non ricevuti da altri nodi"
    LEAVE_SUCCESS=false
fi

if [ "$POST_LEAVE_COUNT" -ne "$EXPECTED_AFTER_LEAVE" ]; then
    log_error "Conteggio post-LEAVE errato: $POST_LEAVE_COUNT (atteso: $EXPECTED_AFTER_LEAVE)"
    LEAVE_SUCCESS=false
fi

if [ "$LEAVE_SUCCESS" = true ]; then
    record_test_result "LEAVE_GRACEFUL" "PASS" "LEAVE inviati: $LEAVE_SENT, ricevuti: $LEAVE_RECEIVED, ${TEST2_DURATION}s"
    log_success "LEAVE GRACEFUL completato in ${TEST2_DURATION}s"
else
    record_test_result "LEAVE_GRACEFUL" "FAIL" "Problemi con LEAVE messages"
    log_error "LEAVE GRACEFUL fallito"
fi

# Pausa inter-test
wait_seconds 10 "Pausa stabilizzazione inter-test..."

# =================================================================
# TEST 3: FAILURE DETECTION COMPLETA
# =================================================================
print_separator
log_test "TEST 3: FAILURE DETECTION COMPLETA"
print_separator

TEST3_START=$(date +%s)
KILL_NODE="node4"
EXPECTED_AFTER_KILL=3

log_info "Stato pre-FAILURE:"
PRE_KILL_COUNT=$(docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")
log_info "Nodi attivi: $PRE_KILL_COUNT"

log_info "Kill improvviso di $KILL_NODE..."

# Kill brutale
CONTAINER_ID=$(docker-compose ps -q $KILL_NODE)
if [ -n "$CONTAINER_ID" ]; then
    docker kill $CONTAINER_ID &>/dev/null
    log_success "$KILL_NODE killato (${CONTAINER_ID:0:12})"
else
    log_error "Container $KILL_NODE non trovato"
    record_test_result "FAILURE_DETECTION" "FAIL" "Container non trovato"
    exit 1
fi

FAILURE_START=$(date +%s)

# Monitoring failure detection
log_info "Monitoring failure detection (max 140s)..."

SUSPECT_DETECTED=false
DEAD_DETECTED=false
REMOVED_DETECTED=false
SUSPECT_TIME=0
DEAD_TIME=0
REMOVED_TIME=0

MAX_WAIT=140
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - FAILURE_START))

    # Check SUSPECT
    if [ "$SUSPECT_DETECTED" = false ]; then
        SUSPECT_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*SUSPECT" | wc -l)
        if [ "$SUSPECT_COUNT" -gt 0 ]; then
            SUSPECT_DETECTED=true
            SUSPECT_TIME=$ELAPSED
            log_success "SUSPECT rilevato dopo ${SUSPECT_TIME}s"
        fi
    fi

    # Check DEAD
    if [ "$SUSPECT_DETECTED" = true ] && [ "$DEAD_DETECTED" = false ]; then
        DEAD_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*DEAD" | wc -l)
        if [ "$DEAD_COUNT" -gt 0 ]; then
            DEAD_DETECTED=true
            DEAD_TIME=$ELAPSED
            log_success "DEAD rilevato dopo ${DEAD_TIME}s"
        fi
    fi

    # Check REMOVED
    if [ "$DEAD_DETECTED" = true ] && [ "$REMOVED_DETECTED" = false ]; then
        REMOVED_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*rimosso" | wc -l)
        if [ "$REMOVED_COUNT" -gt 0 ]; then
            REMOVED_DETECTED=true
            REMOVED_TIME=$ELAPSED
            log_success "REMOVED rilevato dopo ${REMOVED_TIME}s"
            break
        fi
    fi

    printf "\r⏳ Failure detection... %ds [S:%s D:%s R:%s]" \
        $ELAPSED \
        $([ "$SUSPECT_DETECTED" = true ] && echo "✓" || echo "⏳") \
        $([ "$DEAD_DETECTED" = true ] && echo "✓" || echo "⏳") \
        $([ "$REMOVED_DETECTED" = true ] && echo "✓" || echo "⏳")

    sleep 3
done

echo ""

wait_seconds 10 "Stabilizzazione finale post-failure..."

POST_KILL_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

TEST3_END=$(date +%s)
TEST3_DURATION=$((TEST3_END - TEST3_START))

FAILURE_SUCCESS=true
FAILURE_DETAILS=""

if [ "$SUSPECT_DETECTED" = false ]; then
    log_error "SUSPECT mai rilevato"
    FAILURE_SUCCESS=false
    FAILURE_DETAILS+="No-SUSPECT "
fi

if [ "$DEAD_DETECTED" = false ]; then
    log_error "DEAD mai rilevato"
    FAILURE_SUCCESS=false
    FAILURE_DETAILS+="No-DEAD "
fi

if [ "$REMOVED_DETECTED" = false ]; then
    log_error "REMOVED mai rilevato"
    FAILURE_SUCCESS=false
    FAILURE_DETAILS+="No-REMOVED "
fi

if [ "$POST_KILL_COUNT" -ne "$EXPECTED_AFTER_KILL" ]; then
    log_error "Conteggio finale errato: $POST_KILL_COUNT (atteso: $EXPECTED_AFTER_KILL)"
    FAILURE_SUCCESS=false
    FAILURE_DETAILS+="Wrong-count($POST_KILL_COUNT) "
fi

if [ "$FAILURE_SUCCESS" = true ]; then
    record_test_result "FAILURE_DETECTION" "PASS" "S:${SUSPECT_TIME}s D:${DEAD_TIME}s R:${REMOVED_TIME}s, ${TEST3_DURATION}s"
    log_success "FAILURE DETECTION completata in ${TEST3_DURATION}s"
else
    record_test_result "FAILURE_DETECTION" "FAIL" "$FAILURE_DETAILS"
    log_error "FAILURE DETECTION fallita"
fi

# =================================================================
# TEST 4: RESURRECTION
# =================================================================
print_separator
log_test "TEST 4: RESURRECTION"
print_separator

TEST4_START=$(date +%s)

log_info "Test resurrezione di $KILL_NODE..."
docker-compose up -d $KILL_NODE

wait_seconds 25 "Attesa re-join completo..."

RESURRECTION_COUNT=$(docker-compose logs --tail=30 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")
RESURRECTION_SENDING=$(docker-compose logs $KILL_NODE --tail=20 2>/dev/null | grep "GOSSIP.*inviato" | wc -l)
RESURRECTION_RECEIVING=$(docker-compose logs --tail=50 2>/dev/null | grep "GOSSIP.*Ricevuto.*$KILL_NODE" | wc -l)

TEST4_END=$(date +%s)
TEST4_DURATION=$((TEST4_END - TEST4_START))

if [ "$RESURRECTION_COUNT" -eq 4 ] && [ "$RESURRECTION_SENDING" -gt 0 ] && [ "$RESURRECTION_RECEIVING" -gt 0 ]; then
    record_test_result "RESURRECTION" "PASS" "4 nodi, sending:$RESURRECTION_SENDING, receiving:$RESURRECTION_RECEIVING, ${TEST4_DURATION}s"
    log_success "RESURRECTION completata in ${TEST4_DURATION}s"
else
    record_test_result "RESURRECTION" "FAIL" "Count:$RESURRECTION_COUNT, Send:$RESURRECTION_SENDING, Recv:$RESURRECTION_RECEIVING"
    log_error "RESURRECTION fallita"
fi

# =================================================================
# TEST 5: STRESS TEST
# =================================================================
print_separator
log_test "TEST 5: STRESS TEST"
print_separator

TEST5_START=$(date +%s)

log_info "Stress test: operazioni multiple simultanee..."

# Aggiungi node6 e node7 simultaneamente
log_info "JOIN simultaneo di node6 e node7..."
docker-compose up -d node6 node7 &
PARALLEL_PID=$!

wait_seconds 20 "Attesa JOIN multipli..."
wait $PARALLEL_PID

# Verifica conteggio
STRESS_COUNT=$(docker-compose logs --tail=30 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

if [ "$STRESS_COUNT" -eq 6 ]; then
    log_success "JOIN multipli riusciti: $STRESS_COUNT nodi"
    STRESS_JOIN_OK=true
else
    log_warning "JOIN multipli parziali: $STRESS_COUNT nodi (atteso: 6)"
    STRESS_JOIN_OK=false
fi

# LEAVE simultaneo
log_info "LEAVE simultaneo di node6 e node7..."
docker-compose stop node6 node7 &
STOP_PID=$!

wait_seconds 15 "Attesa LEAVE multipli..."
wait $STOP_PID

# Verifica finale
FINAL_STRESS_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

TEST5_END=$(date +%s)
TEST5_DURATION=$((TEST5_END - TEST5_START))

if [ "$STRESS_JOIN_OK" = true ] && [ "$FINAL_STRESS_COUNT" -eq 4 ]; then
    record_test_result "STRESS_TEST" "PASS" "JOIN+LEAVE multipli, ${TEST5_DURATION}s"
    log_success "STRESS TEST completato in ${TEST5_DURATION}s"
else
    record_test_result "STRESS_TEST" "FAIL" "JOIN:$STRESS_JOIN_OK, Final:$FINAL_STRESS_COUNT"
    log_error "STRESS TEST fallito"
fi

# =================================================================
# REPORT FINALE
# =================================================================
TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - TOTAL_START_TIME))

print_separator
echo -e "${PURPLE}📊 REPORT FINALE SUITE COMPLETA${NC}"
print_separator

echo ""
echo "⏱️  Durata totale: ${TOTAL_DURATION}s ($(($TOTAL_DURATION/60))m $(($TOTAL_DURATION%60))s)"
echo "✅ Test passati: $TESTS_PASSED"
echo "❌ Test falliti: $TESTS_FAILED"
echo "📈 Success rate: $(($TESTS_PASSED * 100 / ($TESTS_PASSED + $TESTS_FAILED)))%"

echo ""
echo "📋 Dettaglio risultati:"
for result in "${TEST_RESULTS[@]}"; do
    echo "   $result"
done

echo ""
echo "📊 Stato finale sistema:"
docker-compose ps
echo ""
FINAL_NODE_COUNT=$(docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")
echo "🌐 Nodi attivi nel gossip: $FINAL_NODE_COUNT"

echo ""
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 SUITE COMPLETA: TUTTI I TEST PASSATI! 🎉${NC}"
    FINAL_EXIT=0
else
    echo -e "${RED}💥 SUITE COMPLETA: $TESTS_FAILED TEST FALLITI 💥${NC}"
    FINAL_EXIT=1
fi

echo ""
read -p "🧹 Vuoi fare cleanup finale? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Cleanup finale..."
    docker-compose down -v
    log_success "Cleanup completato"
fi

exit $FINAL_EXIT