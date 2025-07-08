#!/bin/bash
# test_join.sh - Test automatico per JOIN di nuovi nodi

set -e  # Exit on error

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 TEST AUTOMATICO: JOIN${NC}"
echo "=================================="

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
INITIAL_NODES=4
JOIN_NODE="node5"
EXPECTED_FINAL_NODES=5

# Cleanup iniziale
log_info "Cleanup iniziale..."
docker-compose down -v &>/dev/null
sleep 2

# Fase 1: Avvio cluster iniziale
log_info "Avvio cluster iniziale con $INITIAL_NODES nodi..."
docker-compose up -d node1 node2 node3 node4

# Attesa stabilizzazione
wait_seconds 25 "Attesa stabilizzazione cluster iniziale..."

# Verifica cluster iniziale
log_info "Verifica stato cluster iniziale..."
INITIAL_COUNT=$(docker-compose logs --tail=50 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

if [ "$INITIAL_COUNT" -eq "$INITIAL_NODES" ]; then
    log_success "Cluster iniziale stabile: $INITIAL_COUNT nodi"
else
    log_warning "Cluster potrebbe non essere stabile: $INITIAL_COUNT nodi rilevati"
fi

# Fase 2: JOIN del nuovo nodo
log_info "Avvio $JOIN_NODE per test JOIN..."
docker-compose up -d $JOIN_NODE

# Monitoring del JOIN
log_info "Monitoring JOIN in corso..."
JOIN_SUCCESS=false
TIMEOUT=60
COUNTER=0

while [ $COUNTER -lt $TIMEOUT ]; do
    # Verifica se il nuovo nodo sta inviando gossip
    NEW_NODE_SENDING=$(docker-compose logs $JOIN_NODE --tail=20 2>/dev/null | grep "GOSSIP.*Gossip Update inviato" | wc -l)

    # Verifica se altri nodi ricevono dal nuovo nodo
    OTHERS_RECEIVING=$(docker-compose logs --tail=50 2>/dev/null | grep "GOSSIP.*Ricevuto gossip_update da $JOIN_NODE" | wc -l)

    # Verifica conteggio nodi finale
    FINAL_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

    if [ "$NEW_NODE_SENDING" -gt 0 ] && [ "$OTHERS_RECEIVING" -gt 0 ] && [ "$FINAL_COUNT" -eq "$EXPECTED_FINAL_NODES" ]; then
        JOIN_SUCCESS=true
        break
    fi

    printf "\r⏳ JOIN progress... %ds (%d/5 nodi)" $COUNTER $FINAL_COUNT
    sleep 2
    ((COUNTER+=2))
done

echo ""

# Risultati JOIN
if [ "$JOIN_SUCCESS" = true ]; then
    log_success "JOIN completato con successo!"
    log_success "$JOIN_NODE sta inviando gossip: $NEW_NODE_SENDING messaggi"
    log_success "Altri nodi ricevono da $JOIN_NODE: $OTHERS_RECEIVING volte"
    log_success "Conteggio finale nodi: $FINAL_COUNT"
else
    log_error "JOIN fallito o incompleto dopo ${TIMEOUT}s"
    log_error "$JOIN_NODE inviando gossip: $NEW_NODE_SENDING"
    log_error "Altri ricevendo da $JOIN_NODE: $OTHERS_RECEIVING"
    log_error "Conteggio nodi attuale: $FINAL_COUNT"
fi

# Verifica dettagliata finale
echo ""
log_info "=== DETTAGLI FINALI ==="
echo "📊 Ultimi messaggi gossip:"
docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -3

echo ""
echo "📊 Attività di $JOIN_NODE:"
docker-compose logs $JOIN_NODE --tail=5 2>/dev/null | grep -E "(BOOTSTRAP|GOSSIP)"

echo ""
echo "📊 Altri nodi che vedono $JOIN_NODE:"
docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*Ricevuto gossip_update da $JOIN_NODE" | tail -3

# Status finale containers
echo ""
log_info "Status containers finali:"
docker-compose ps

# Cleanup opzionale
echo ""
read -p "🧹 Vuoi fare cleanup finale? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose down -v
    log_success "Cleanup completato"
fi

if [ "$JOIN_SUCCESS" = true ]; then
    echo -e "\n${GREEN}🎉 TEST JOIN: PASSATO! 🎉${NC}"
    exit 0
else
    echo -e "\n${RED}💥 TEST JOIN: FALLITO! 💥${NC}"
    exit 1
fi