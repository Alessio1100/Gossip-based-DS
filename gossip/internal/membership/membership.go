package membership

import (
	"Gossip/internal/util"
	"sync"
	"time"
)

// Struttura della Membership List
type MembershipList struct {
	members map[string]util.NodeStatus // mappa da ID nodo a NodeStatus
	mutex   sync.RWMutex               // mutex per accesso concorrente sicuro
}

// Costruttore: crea una nuova Membership List vuota
func NewMembershipList() *MembershipList {
	return &MembershipList{
		members: make(map[string]util.NodeStatus),
	}
}

// ✅ Aggiunge un nuovo nodo o aggiorna un nodo esistente
func (ml *MembershipList) AddOrUpdateNode(node util.NodeStatus) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	existing, exists := ml.members[node.ID]

	if !exists {
		// Nodo nuovo: aggiungilo
		ml.members[node.ID] = node
		return
	}

	// ✅ LOGICA SMART per gestire conflitti di stato

	// Parse dei timestamp per confronto
	existingTime, errExisting := time.Parse(time.RFC3339, existing.LastSeen)
	newTime, errNew := time.Parse(time.RFC3339, node.LastSeen)

	if errExisting != nil || errNew != nil {
		// Se errore nel parsing, usa quello più recente come stringa
		if node.LastSeen > existing.LastSeen {
			ml.members[node.ID] = node
		}
		return
	}

	// ✅ REGOLE per risolvere conflitti di stato:

	// 1. Se ricevo info più recente, aggiorna sempre
	if newTime.After(existingTime) {
		ml.members[node.ID] = node
		return
	}

	// 2. Se stesso timestamp, usa la precedenza degli stati
	if newTime.Equal(existingTime) {
		// Precedenza: ALIVE > SUSPECT > DEAD
		if shouldUpdateState(existing.Status, node.Status) {
			existing.Status = node.Status
			ml.members[node.ID] = existing
		}
		return
	}

	// 3. Se ricevo info più vecchia, aggiorna solo se è "migliore"
	if newTime.Before(existingTime) {
		// Solo se lo stato ricevuto è "migliore" (es. ALIVE vs SUSPECT)
		if shouldUpdateState(existing.Status, node.Status) {
			// Mantieni il timestamp più recente ma aggiorna lo stato
			existing.Status = node.Status
			ml.members[node.ID] = existing
		}
	}
}

func shouldUpdateState(currentStatus, newStatus string) bool {
	// Mappa priorità stati: ALIVE > SUSPECT > DEAD
	priority := map[string]int{
		"alive":   3,
		"suspect": 2,
		"dead":    1,
	}

	currentPrio, okCurrent := priority[currentStatus]
	newPrio, okNew := priority[newStatus]

	if !okCurrent || !okNew {
		return false
	}

	// Aggiorna solo se il nuovo stato ha priorità maggiore (è "migliore")
	return newPrio > currentPrio
}

// ✅ Rimuove un nodo dalla lista
func (ml *MembershipList) RemoveNode(nodeID string) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	delete(ml.members, nodeID)
}

// ✅ Marca un nodo come SUSPECT
func (ml *MembershipList) MarkNodeSuspect(nodeID string) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	if node, exists := ml.members[nodeID]; exists && node.Status != "dead" {
		node.Status = "suspect"
		ml.members[nodeID] = node
	}
}

// ✅ Marca un nodo come DEAD
func (ml *MembershipList) MarkNodeDead(nodeID string) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	if node, exists := ml.members[nodeID]; exists {
		node.Status = "dead"
		ml.members[nodeID] = node
	}
}

// ✅ Ritorna una copia sicura della Membership List (per Gossip Update)
func (ml *MembershipList) GetCopy() []util.NodeStatus {
	ml.mutex.RLock()
	defer ml.mutex.RUnlock()

	list := make([]util.NodeStatus, 0, len(ml.members))
	for _, node := range ml.members {
		list = append(list, node)
	}
	return list
}

// ✅ Restituisce il timestamp "LastSeen" per un nodo specifico (utile per Failure Detection)
func (ml *MembershipList) GetLastSeen(nodeID string) (string, bool) {
	ml.mutex.RLock()
	defer ml.mutex.RUnlock()

	node, exists := ml.members[nodeID]
	if !exists {
		return "", false
	}
	return node.LastSeen, true
}

// ✅ Restituisce lo stato (alive, suspect, dead) di un nodo specifico
func (ml *MembershipList) GetNodeStatus(nodeID string) (string, bool) {
	ml.mutex.RLock()
	defer ml.mutex.RUnlock()

	node, exists := ml.members[nodeID]
	if !exists {
		return "", false
	}
	return node.Status, true
}

// ✅ Aggiorna il timestamp "LastSeen" di un nodo (per heartbeat implicito via Gossip Update)
func (ml *MembershipList) UpdateLastSeen(nodeID string) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	if node, exists := ml.members[nodeID]; exists && node.Status != "dead" {
		node.LastSeen = time.Now().Format(time.RFC3339)
		node.Status = "alive" // Se ricevo da lui, lo considero vivo
		ml.members[nodeID] = node
	}
}

// ✅ Merge della Membership List ricevuta con quella locale
func (ml *MembershipList) MergeMembership(receivedList []util.NodeStatus) {
	ml.mutex.Lock()
	defer ml.mutex.Unlock()

	for _, receivedNode := range receivedList {
		existingNode, exists := ml.members[receivedNode.ID]

		// Se il nodo non esiste, o se il LastSeen ricevuto è più recente, aggiorniamo
		if !exists || receivedNode.LastSeen > existingNode.LastSeen {
			ml.members[receivedNode.ID] = receivedNode
		}
	}
}

// ✅ Ritorna l'intero contenuto della mappa (per Debug)
func (ml *MembershipList) Print() map[string]util.NodeStatus {
	ml.mutex.RLock()
	defer ml.mutex.RUnlock()

	copyMap := make(map[string]util.NodeStatus)
	for id, status := range ml.members {
		copyMap[id] = status
	}
	return copyMap
}
