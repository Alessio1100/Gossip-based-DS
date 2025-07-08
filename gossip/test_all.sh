#!/bin/bash
# test_integrated.sh - Scenario integrato: Ciclo di vita completo del cluster

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${PURPLE}🌟 TEST SCENARIO INTEGRATO: CICLO DI VITA CLUSTER 🌟${NC}"
echo "================================================================="

# Funzioni utility
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_scenario() { echo -e "${CYAN}🎬 $1${NC}"; }

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

# Funzione per ottenere stato cluster
get_cluster_status() {
    local node_count=$(docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | sed -n 's/.*con \([0-9]*\) nodi.*/\1/p' || echo "0")
    local active_containers=$(docker-compose ps --format "{{.Names}}" | grep -c "node" || echo "0")
    local gossip_activity=$(docker-compose logs --tail=20 2>/dev/null | grep -c "GOSSIP.*inviato\|GOSSIP.*Ricevuto" || echo "0")

    echo "📊 STATO CLUSTER: $node_count nodi gossip, $active_containers container, $gossip_activity messaggi"

    # Return values
    export CLUSTER_NODES=$node_count
    export CLUSTER_CONTAINERS=$active_containers
    export CLUSTER_ACTIVITY=$gossip_activity
}

# Cleanup iniziale
log_info "Preparazione ambiente di test..."
docker-compose down -v --remove-orphans &>/dev/null || true
docker system prune -f --volumes &>/dev/null || true
sleep 3

echo ""
echo "📋 SCENARIO: SIMULAZIONE REALISTICA DI UN CLUSTER IN PRODUZIONE"
echo ""
echo "🎬 ATTO 1: Bootstrap e crescita del cluster"
echo "🎬 ATTO 2: Operazioni normali e manutenzione"
echo "🎬 ATTO 3: Gestione failure e recovery"
echo "🎬 ATTO 4: Stabilizzazione finale"
echo ""
read -p "🚀 Iniziare la simulazione? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Simulazione annullata."
    exit 0
fi

# Tracciamento eventi
EVENTS_LOG=()
SCENARIO_START=$(date +%s)

# =================================================================
# ATTO 1: BOOTSTRAP E CRESCITA DEL CLUSTER
# =================================================================
echo ""
log_scenario "ATTO 1: BOOTSTRAP E CRESCITA DEL CLUSTER"
echo "================================================================="

# Inizio con cluster minimo
log_info "T+0s: Avvio nodi bootstrap (node1, node2)"
docker-compose up -d node1 node2
EVENTS_LOG+=("T+0s: Bootstrap cluster con node1 e node2")

wait_seconds 15 "Bootstrap iniziale..."
get_cluster_status
EVENTS_LOG+=("T+15s: Cluster bootstrap - $CLUSTER_NODES nodi gossip")

# Espansione graduale del cluster
log_info "T+20s: Espansione cluster - aggiunta node3"
docker-compose up -d node3
EVENTS_LOG+=("T+20s: JOIN node3")

wait_seconds 10 "Propagazione JOIN node3..."
get_cluster_status
EVENTS_LOG+=("T+30s: Cluster post-JOIN node3 - $CLUSTER_NODES nodi")

log_info "T+35s: Crescita continua - aggiunta node4"
docker-compose up -d node4
EVENTS_LOG+=("T+35s: JOIN node4")

wait_seconds 10 "Propagazione JOIN node4..."
get_cluster_status
EVENTS_LOG+=("T+45s: Cluster post-JOIN node4 - $CLUSTER_NODES nodi")

log_info "T+50s: Completamento cluster - aggiunta node5"
docker-compose up -d node5
EVENTS_LOG+=("T+50s: JOIN node5")

wait_seconds 15 "Stabilizzazione cluster completo..."
get_cluster_status
CLUSTER_FULL_SIZE=$CLUSTER_NODES
EVENTS_LOG+=("T+65s: Cluster completo - $CLUSTER_NODES nodi attivi")

log_success "ATTO 1 COMPLETATO: Cluster cresciuto da 2 a $CLUSTER_FULL_SIZE nodi"

# =================================================================
# ATTO 2: OPERAZIONI NORMALI E MANUTENZIONE
# =================================================================
echo ""
log_scenario "ATTO 2: OPERAZIONI NORMALI E MANUTENZIONE"
echo "================================================================="

log_info "T+70s: Periodo di operazioni normali..."
wait_seconds 20 "Osservazione traffico gossip normale..."

get_cluster_status
EVENTS_LOG+=("T+90s: Operazioni normali - $CLUSTER_ACTIVITY messaggi gossip")

log_info "T+95s: Manutenzione programmata - LEAVE graceful di node3"
EVENTS_LOG+=("T+95s: LEAVE programmato node3")

# Cattura logs LEAVE
timeout 8s docker-compose logs -f node3 2>/dev/null | grep "LEAVE\|EXIT" &
CAPTURE_PID=$!

docker-compose stop node3
wait_seconds 5 "Elaborazione LEAVE..."
kill $CAPTURE_PID 2>/dev/null || true

wait_seconds 15 "Propagazione e stabilizzazione post-LEAVE..."
get_cluster_status
EVENTS_LOG+=("T+115s: Post-LEAVE - $CLUSTER_NODES nodi, $CLUSTER_CONTAINERS container")

log_success "ATTO 2 COMPLETATO: Manutenzione graceful eseguita con successo"

# =================================================================
# ATTO 3: GESTIONE FAILURE E RECOVERY
# =================================================================
echo ""
log_scenario "ATTO 3: GESTIONE FAILURE E RECOVERY"
echo "================================================================="

log_info "T+120s: Periodo di stabilità post-manutenzione..."
wait_seconds 10 "Stabilizzazione..."

get_cluster_status
STABLE_COUNT=$CLUSTER_NODES
EVENTS_LOG+=("T+130s: Cluster stabile - $STABLE_COUNT nodi")

log_warning "T+135s: EVENTO CRITICO - Failure improvviso di node4!"
CONTAINER_ID=$(docker-compose ps -q node4)
EVENTS_LOG+=("T+135s: FAILURE improvviso node4")

if [ -n "$CONTAINER_ID" ]; then
    docker kill $CONTAINER_ID &>/dev/null
    log_error "node4 terminato improvvisamente (simula crash hardware)"
else
    log_error "Container node4 non trovato per failure test"
fi

# Monitoring della failure detection in tempo reale
log_info "T+140s: Monitoring failure detection..."
FAILURE_START=$(date +%s)
DETECTION_FOUND=false

for i in {1..12}; do  # 60 secondi di monitoring
    sleep 5
    ELAPSED=$((5 * i))

    # Verifica detection
    FAILURE_MSGS=$(docker-compose logs --since="$FAILURE_START" 2>/dev/null | grep -c "FAILURE.*node4" || echo "0")

    if [ "$FAILURE_MSGS" -gt 0 ] && [ "$DETECTION_FOUND" = false ]; then
        DETECTION_FOUND=true
        log_success "T+$((135 + ELAPSED))s: Failure detection attivata! ($FAILURE_MSGS messaggi)"
        EVENTS_LOG+=("T+$((135 + ELAPSED))s: Failure detection - node4 rilevato come failed")
        break
    fi

    printf "\r⏳ Monitoring failure detection... %ds" $ELAPSED
done

echo ""

get_cluster_status
EVENTS_LOG+=("T+200s: Post-failure - $CLUSTER_NODES nodi gossip, $CLUSTER_CONTAINERS container")

# Recovery: Resurrezione del nodo
log_info "T+205s: RECOVERY - Riavvio node4 (simula riparazione hardware)"
docker-compose up -d node4
EVENTS_LOG+=("T+205s: RECOVERY node4 - riavvio dopo failure")

wait_seconds 20 "Recovery e re-join..."
get_cluster_status
EVENTS_LOG+=("T+225s: Post-recovery - $CLUSTER_NODES nodi, $CLUSTER_CONTAINERS container")

log_success "ATTO 3 COMPLETATO: Failure detection e recovery eseguiti"

# =================================================================
# ATTO 4: STABILIZZAZIONE FINALE
# =================================================================
echo ""
log_scenario "ATTO 4: STABILIZZAZIONE E VERIFICA FINALE"
echo "================================================================="

log_info "T+230s: Verifica stabilità finale del cluster..."
wait_seconds 25 "Stabilizzazione finale..."

get_cluster_status
FINAL_NODES=$CLUSTER_NODES
FINAL_CONTAINERS=$CLUSTER_CONTAINERS
FINAL_ACTIVITY=$CLUSTER_ACTIVITY

EVENTS_LOG+=("T+255s: STATO FINALE - $FINAL_NODES nodi gossip, $FINAL_CONTAINERS container")

# Test finale di resilienza
log_info "T+260s: Test finale - aggiunta last-minute di node6"
docker-compose up -d node6
EVENTS_LOG+=("T+260s: JOIN finale node6")

wait_seconds 15 "Integrazione node6..."
get_cluster_status
EVENTS_LOG+=("T+275s: CLUSTER FINALE - $CLUSTER_NODES nodi totali")

log_success "ATTO 4 COMPLETATO: Cluster stabilizzato e testato"

# =================================================================
# ANALISI FINALE E VALUTAZIONE
# =================================================================
SCENARIO_END=$(date +%s)
TOTAL_DURATION=$((SCENARIO_END - SCENARIO_START))

echo ""
echo "================================================================="
log_scenario "📊 ANALISI FINALE DELLO SCENARIO"
echo "================================================================="

echo ""
echo "⏱️  Durata totale simulazione: ${TOTAL_DURATION}s ($(($TOTAL_DURATION/60))m $(($TOTAL_DURATION%60))s)"
echo "🎬 Eventi simulati: ${#EVENTS_LOG[@]}"
echo "🔧 Operazioni testate: JOIN, LEAVE, FAILURE, RECOVERY"
echo ""

echo "📋 CRONOLOGIA EVENTI:"
for event in "${EVENTS_LOG[@]}"; do
    echo "   📍 $event"
done

echo ""
echo "🏆 VALUTAZIONE SCENARIO:"

# Criteri di successo dello scenario integrato
SUCCESS_CRITERIA=0
TOTAL_CRITERIA=5

echo ""
echo "📊 Criteri di successo:"

# 1. Cluster crescita (JOIN multipli)
if [ "$CLUSTER_FULL_SIZE" -ge 4 ]; then
    echo "✅ 1. Crescita cluster: $CLUSTER_FULL_SIZE nodi raggiunti"
    ((SUCCESS_CRITERIA++))
else
    echo "❌ 1. Crescita cluster: solo $CLUSTER_FULL_SIZE nodi (target: ≥4)"
fi

# 2. Manutenzione LEAVE
LEAVE_EVIDENCE=$(docker-compose logs 2>/dev/null | grep -c "LEAVE.*node3" || echo "0")
if [ "$LEAVE_EVIDENCE" -gt 0 ]; then
    echo "✅ 2. Manutenzione LEAVE: $LEAVE_EVIDENCE evidenze"
    ((SUCCESS_CRITERIA++))
else
    echo "❌ 2. Manutenzione LEAVE: nessuna evidenza"
fi

# 3. Failure detection
if [ "$DETECTION_FOUND" = true ]; then
    echo "✅ 3. Failure detection: attivata correttamente"
    ((SUCCESS_CRITERIA++))
else
    echo "❌ 3. Failure detection: non rilevata"
fi

# 4. Recovery
if [ "$FINAL_CONTAINERS" -ge 4 ]; then
    echo "✅ 4. Recovery: $FINAL_CONTAINERS container attivi"
    ((SUCCESS_CRITERIA++))
else
    echo "❌ 4. Recovery: solo $FINAL_CONTAINERS container attivi"
fi

# 5. Stabilità finale
if [ "$FINAL_ACTIVITY" -gt 10 ]; then
    echo "✅ 5. Stabilità finale: $FINAL_ACTIVITY messaggi gossip attivi"
    ((SUCCESS_CRITERIA++))
else
    echo "❌ 5. Stabilità finale: solo $FINAL_ACTIVITY messaggi gossip"
fi

# Calcolo score finale
SCORE_PERCENTAGE=$((SUCCESS_CRITERIA * 100 / TOTAL_CRITERIA))

echo ""
echo "📈 SCORE FINALE: $SUCCESS_CRITERIA/$TOTAL_CRITERIA criteri soddisfatti ($SCORE_PERCENTAGE%)"

if [ $SCORE_PERCENTAGE -eq 100 ]; then
    echo -e "${GREEN}🏆 ECCELLENTE: Sistema gossip supera scenario completo!${NC}"
    GRADE="A+"
elif [ $SCORE_PERCENTAGE -ge 80 ]; then
    echo -e "${YELLOW}🥇 OTTIMO: Sistema gossip gestisce bene scenari complessi${NC}"
    GRADE="A"
elif [ $SCORE_PERCENTAGE -ge 60 ]; then
    echo -e "${YELLOW}🥈 BUONO: Sistema gossip funzionale con miglioramenti minori${NC}"
    GRADE="B"
else
    echo -e "${RED}🥉 SUFFICIENTE: Sistema gossip richiede miglioramenti${NC}"
    GRADE="C"
fi

echo "🎓 Voto scenario integrato: $GRADE"

echo ""
read -p "🧹 Cleanup finale dell'ambiente? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log_info "Cleanup finale..."
    docker-compose down -v --remove-orphans &>/dev/null || true
    log_success "Ambiente pulito"
fi

echo ""
echo -e "${PURPLE}🌟 SCENARIO INTEGRATO COMPLETATO 🌟${NC}"
echo "================================================================="

# Exit code basato sul successo
if [ $SCORE_PERCENTAGE -ge 80 ]; then
    exit 0
else
    exit 1
fi