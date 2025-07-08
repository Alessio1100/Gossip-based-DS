#!/bin/bash
# test_failure.sh - Test automatico per FAILURE detection

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 TEST AUTOMATICO: FAILURE DETECTION${NC}"
echo "============================================="

# Funzioni utility
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

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

# Test variables
TOTAL_NODES=5
KILL_NODE="node4"
EXPECTED_REMAINING=4
SUSPECT_TIMEOUT=30
DEAD_TIMEOUT=60
REMOVE_TIMEOUT=120

# Cleanup iniziale
log_info "Cleanup iniziale..."
docker-compose down -v &>/dev/null
sleep 2

# Fase 1: Avvio cluster completo
log_info "Avvio cluster completo con $TOTAL_NODES nodi..."
docker-compose up -d node1 node2 node3 node4 node5

# Attesa stabilizzazione
wait_seconds 30 "Attesa stabilizzazione cluster completo..."

# Verifica cluster iniziale
INITIAL_COUNT=$(docker-compose logs --tail=50 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

if [ "$INITIAL_COUNT" -eq "$TOTAL_NODES" ]; then
    log_success "Cluster stabile: $INITIAL_COUNT nodi"
else
    log_warning "Cluster potrebbe non essere stabile: $INITIAL_COUNT nodi"
fi

# Salva stato pre-failure
echo ""
log_info "📊 Stato PRE-FAILURE:"
docker-compose logs --tail=5 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -2

# Fase 2: Kill improvviso
log_info "Kill improvviso di $KILL_NODE (simula crash)..."

# Ottieni container ID
CONTAINER_ID=$(docker-compose ps -q $KILL_NODE)
if [ -z "$CONTAINER_ID" ]; then
    log_error "Container $KILL_NODE non trovato!"
    exit 1
fi

# Kill brutale
docker kill $CONTAINER_ID &>/dev/null
log_success "$KILL_NODE killato (ID: ${CONTAINER_ID:0:12})"

# Timestamp di inizio failure
FAILURE_START=$(date +%s)

# Fase 3: Monitoring failure detection
log_info "Monitoring failure detection in tempo reale..."

# Variabili di stato
SUSPECT_DETECTED=false
DEAD_DETECTED=false
REMOVED_DETECTED=false
SUSPECT_TIME=0
DEAD_TIME=0
REMOVED_TIME=0

# Monitoring loop (max 150 secondi)
MAX_WAIT=150
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - FAILURE_START))

    # Check per SUSPECT
    if [ "$SUSPECT_DETECTED" = false ]; then
        SUSPECT_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*marcato come SUSPECT" | wc -l)
        if [ "$SUSPECT_COUNT" -gt 0 ]; then
            SUSPECT_DETECTED=true
            SUSPECT_TIME=$ELAPSED
            log_success "SUSPECT rilevato dopo ${SUSPECT_TIME}s (atteso: ~${SUSPECT_TIMEOUT}s)"
        fi
    fi

    # Check per DEAD
    if [ "$SUSPECT_DETECTED" = true ] && [ "$DEAD_DETECTED" = false ]; then
        DEAD_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*marcato come DEAD" | wc -l)
        if [ "$DEAD_COUNT" -gt 0 ]; then
            DEAD_DETECTED=true
            DEAD_TIME=$ELAPSED
            log_success "DEAD rilevato dopo ${DEAD_TIME}s (atteso: ~${DEAD_TIMEOUT}s)"
        fi
    fi

    # Check per REMOVED
    if [ "$DEAD_DETECTED" = true ] && [ "$REMOVED_DETECTED" = false ]; then
        REMOVED_COUNT=$(docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE.*rimosso dalla Membership List" | wc -l)
        if [ "$REMOVED_COUNT" -gt 0 ]; then
            REMOVED_DETECTED=true
            REMOVED_TIME=$ELAPSED
            log_success "REMOVED rilevato dopo ${REMOVED_TIME}s (atteso: ~${REMOVE_TIMEOUT}s)"
            break
        fi
    fi

    # Progress indicator
    printf "\r⏳ Failure detection progress... %ds [S:%s D:%s R:%s]" \
        $ELAPSED \
        $([ "$SUSPECT_DETECTED" = true ] && echo "✅" || echo "⏳") \
        $([ "$DEAD_DETECTED" = true ] && echo "✅" || echo "⏳") \
        $([ "$REMOVED_DETECTED" = true ] && echo "✅" || echo "⏳")

    sleep 2
done

echo ""

# Fase 4: Verifica finale
log_info "Verifica finale sistema post-failure..."

wait_seconds 10 "Attesa stabilizzazione finale..."

FINAL_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

# Risultati
echo ""
log_info "=== RISULTATI FAILURE DETECTION ==="

FAILURE_SUCCESS=true

# Verifica SUSPECT
if [ "$SUSPECT_DETECTED" = true ]; then
    if [ $SUSPECT_TIME -le $((SUSPECT_TIMEOUT + 10)) ]; then
        log_success "SUSPECT timing corretto: ${SUSPECT_TIME}s (limite: ${SUSPECT_TIMEOUT}s)"
    else
        log_warning "SUSPECT tardivo: ${SUSPECT_TIME}s (atteso: ~${SUSPECT_TIMEOUT}s)"
    fi
else
    log_error "SUSPECT MAI rilevato dopo ${ELAPSED}s"
    FAILURE_SUCCESS=false
fi

# Verifica DEAD
if [ "$DEAD_DETECTED" = true ]; then
    if [ $DEAD_TIME -le $((DEAD_TIMEOUT + 15)) ]; then
        log_success "DEAD timing corretto: ${DEAD_TIME}s (limite: ${DEAD_TIMEOUT}s)"
    else
        log_warning "DEAD tardivo: ${DEAD_TIME}s (atteso: ~${DEAD_TIMEOUT}s)"
    fi
else
    log_error "DEAD MAI rilevato dopo ${ELAPSED}s"
    FAILURE_SUCCESS=false
fi

# Verifica REMOVED
if [ "$REMOVED_DETECTED" = true ]; then
    if [ $REMOVED_TIME -le $((REMOVE_TIMEOUT + 20)) ]; then
        log_success "REMOVED timing corretto: ${REMOVED_TIME}s (limite: ${REMOVE_TIMEOUT}s)"
    else
        log_warning "REMOVED tardivo: ${REMOVED_TIME}s (atteso: ~${REMOVE_TIMEOUT}s)"
    fi
else
    log_error "REMOVED MAI rilevato dopo ${ELAPSED}s"
    FAILURE_SUCCESS=false
fi

# Verifica conteggio finale
if [ "$FINAL_COUNT" -eq "$EXPECTED_REMAINING" ]; then
    log_success "Conteggio finale corretto: $FINAL_COUNT nodi"
else
    log_error "Conteggio finale errato: $FINAL_COUNT (atteso: $EXPECTED_REMAINING)"
    FAILURE_SUCCESS=false
fi

# Dettagli finali
echo ""
log_info "=== DETTAGLI FINALI ==="
echo "📊 Timeline failure detection:"
docker-compose logs --since="$(date -d @$FAILURE_START -Iseconds)" 2>/dev/null | grep "FAILURE.*$KILL_NODE" | head -10

echo ""
echo "📊 Ultimi conteggi nodi:"
docker-compose logs --tail=5 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -3

echo ""
echo "📊 Status containers (dovrebbe mancare $KILL_NODE):"
docker-compose ps

# Verifica che il container sia effettivamente morto
CONTAINER_RUNNING=$(docker-compose ps $KILL_NODE | grep "Up" | wc -l)
if [ "$CONTAINER_RUNNING" -eq 0 ]; then
    log_success "$KILL_NODE è effettivamente morto"
else
    log_error "$KILL_NODE sembra ancora in esecuzione"
    FAILURE_SUCCESS=false
fi

# Test bonus: Resurrezione
echo ""
read -p "🧟 Vuoi testare la resurrezione di $KILL_NODE? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Riavvio $KILL_NODE per test resurrezione..."
    docker-compose up -d $KILL_NODE

    wait_seconds 20 "Attesa re-join..."

    RESURRECTED_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

    if [ "$RESURRECTED_COUNT" -eq "$TOTAL_NODES" ]; then
        log_success "Resurrezione riuscita: $RESURRECTED_COUNT nodi"
    else
        log_warning "Resurrezione incompleta: $RESURRECTED_COUNT nodi"
    fi
fi

# Cleanup opzionale
echo ""
read -p "🧹 Vuoi fare cleanup finale? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose down -v
    log_success "Cleanup completato"
fi

if [ "$FAILURE_SUCCESS" = true ]; then
    echo -e "\n${GREEN}🎉 TEST FAILURE: PASSATO! 🎉${NC}"
    exit 0
else
    echo -e "\n${RED}💥 TEST FAILURE: FALLITO! 💥${NC}"
    exit 1
fi