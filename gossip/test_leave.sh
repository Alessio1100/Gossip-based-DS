#!/bin/bash
# test_leave.sh - Test automatico per LEAVE graceful

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 TEST AUTOMATICO: LEAVE${NC}"
echo "==================================="

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
LEAVE_NODE="node3"
EXPECTED_REMAINING=4

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
log_info "Verifica stato cluster iniziale..."
INITIAL_COUNT=$(docker-compose logs --tail=50 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

if [ "$INITIAL_COUNT" -eq "$TOTAL_NODES" ]; then
    log_success "Cluster stabile: $INITIAL_COUNT nodi"
else
    log_warning "Cluster potrebbe non essere completamente stabile: $INITIAL_COUNT nodi"
fi

# Salva stato pre-leave
echo ""
log_info "📊 Stato PRE-LEAVE:"
docker-compose logs --tail=5 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -2

# Fase 2: LEAVE graceful
log_info "Esecuzione LEAVE graceful di $LEAVE_NODE..."

# Capture logs prima del leave
timeout 3s docker-compose logs -f $LEAVE_NODE 2>/dev/null | grep -E "(EXIT|LEAVE)" &
LEAVE_LOG_PID=$!

# Esegui graceful stop
docker-compose stop $LEAVE_NODE

# Attendi che i log di leave vengano catturati
wait_seconds 5 "Attesa elaborazione LEAVE messages..."

# Uccidi il processo di logging se ancora attivo
kill $LEAVE_LOG_PID 2>/dev/null || true

# Fase 3: Verifica LEAVE
log_info "Verifica LEAVE in corso..."

# Verifica che il nodo abbia inviato LEAVE messages
LEAVE_SENT=$(docker-compose logs $LEAVE_NODE 2>/dev/null | grep "LEAVE.*Messaggio LEAVE inviato" | wc -l)
LEAVE_EXIT=$(docker-compose logs $LEAVE_NODE 2>/dev/null | grep "EXIT.*LEAVE alla rete" | wc -l)

# Verifica che altri nodi abbiano ricevuto LEAVE
LEAVE_RECEIVED=$(docker-compose logs 2>/dev/null | grep "LEAVE.*Ricevuto messaggio LEAVE da.*$LEAVE_NODE" | wc -l)
LEAVE_REMOVED=$(docker-compose logs 2>/dev/null | grep "LEAVE.*rimosso dalla Membership List" | wc -l)

# Attesa propagazione
wait_seconds 30 "Attesa propagazione rimozione via gossip..."

# Verifica conteggio finale
FINAL_COUNT=$(docker-compose logs --tail=20 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -1 | grep -o "con [0-9]* nodi" | grep -o "[0-9]*" || echo "0")

# Risultati
echo ""
log_info "=== RISULTATI LEAVE ==="

LEAVE_SUCCESS=true

if [ "$LEAVE_SENT" -gt 0 ]; then
    log_success "$LEAVE_NODE ha inviato LEAVE messages: $LEAVE_SENT"
else
    log_error "$LEAVE_NODE NON ha inviato LEAVE messages"
    LEAVE_SUCCESS=false
fi

if [ "$LEAVE_EXIT" -gt 0 ]; then
    log_success "$LEAVE_NODE ha mostrato messaggio EXIT corretto"
else
    log_error "$LEAVE_NODE NON ha mostrato messaggio EXIT"
    LEAVE_SUCCESS=false
fi

if [ "$LEAVE_RECEIVED" -gt 0 ]; then
    log_success "Altri nodi hanno ricevuto LEAVE: $LEAVE_RECEIVED volte"
else
    log_error "Altri nodi NON hanno ricevuto LEAVE messages"
    LEAVE_SUCCESS=false
fi

if [ "$LEAVE_REMOVED" -gt 0 ]; then
    log_success "Nodi hanno rimosso $LEAVE_NODE: $LEAVE_REMOVED volte"
else
    log_error "Nodi NON hanno rimosso $LEAVE_NODE dalla membership"
    LEAVE_SUCCESS=false
fi

if [ "$FINAL_COUNT" -eq "$EXPECTED_REMAINING" ]; then
    log_success "Conteggio finale corretto: $FINAL_COUNT nodi"
else
    log_error "Conteggio finale errato: $FINAL_COUNT (atteso: $EXPECTED_REMAINING)"
    LEAVE_SUCCESS=false
fi

# Dettagli finali
echo ""
log_info "=== DETTAGLI FINALI ==="
echo "📊 LEAVE messages dal nodo uscente:"
docker-compose logs $LEAVE_NODE 2>/dev/null | grep -E "(EXIT|LEAVE)" | tail -5

echo ""
echo "📊 LEAVE messages ricevuti da altri:"
docker-compose logs 2>/dev/null | grep "LEAVE.*$LEAVE_NODE" | tail -3

echo ""
echo "📊 Ultimi conteggi nodi:"
docker-compose logs --tail=10 2>/dev/null | grep "GOSSIP.*con.*nodi" | tail -3

echo ""
echo "📊 Status containers:"
docker-compose ps

# Verifica che il container sia effettivamente fermo
CONTAINER_RUNNING=$(docker-compose ps $LEAVE_NODE | grep "Up" | wc -l)
if [ "$CONTAINER_RUNNING" -eq 0 ]; then
    log_success "$LEAVE_NODE è effettivamente fermo"
else
    log_error "$LEAVE_NODE sembra ancora in esecuzione"
    LEAVE_SUCCESS=false
fi

# Cleanup opzionale
echo ""
read -p "🧹 Vuoi fare cleanup finale? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose down -v
    log_success "Cleanup completato"
fi

if [ "$LEAVE_SUCCESS" = true ]; then
    echo -e "\n${GREEN}🎉 TEST LEAVE: PASSATO! 🎉${NC}"
    exit 0
else
    echo -e "\n${RED}💥 TEST LEAVE: FALLITO! 💥${NC}"
    exit 1
fi