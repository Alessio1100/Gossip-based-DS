package failure

import (
	"Gossip/internal/util"
	"log"
	"time"

	"Gossip/internal/membership"
)

// ✅ Avvia il Failure Detector che controlla periodicamente i nodi sospetti/morti
func StartFailureDetector(localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	ticker := time.NewTicker(10 * time.Second) // ✅ Controllo ogni 10 secondi
	defer ticker.Stop()

	log.Println("[FAILURE] Failure Detector avviato.")

	for {
		<-ticker.C
		checkForFailedNodes(localMembership, selfNode)
	}
}

// ✅ Controlla tutti i nodi e marca quelli sospetti/morti in base ai timeout
func checkForFailedNodes(localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	now := time.Now()
	nodes := localMembership.GetCopy()

	for _, node := range nodes {
		// ✅ SKIP del proprio nodo
		if node.ID == selfNode.ID {
			continue
		}

		// Parse del timestamp LastSeen
		lastSeen, err := time.Parse(time.RFC3339, node.LastSeen)
		if err != nil {
			log.Printf("[FAILURE] Errore parsing timestamp per nodo %s: %v", node.ID, err)
			continue
		}

		timeSinceLastSeen := now.Sub(lastSeen)

		// ✅ LOGICA NORMALE (non aggressiva):

		// Se nodo ALIVE e non visto da 30 secondi → SUSPECT
		if node.Status == "alive" && timeSinceLastSeen > 30*time.Second {
			localMembership.MarkNodeSuspect(node.ID)
			log.Printf("[FAILURE] Nodo %s marcato come SUSPECT (non visto da %v)", node.ID, timeSinceLastSeen)
		}

		// Se nodo SUSPECT e non visto da 60 secondi → DEAD
		if node.Status == "suspect" && timeSinceLastSeen > 60*time.Second {
			localMembership.MarkNodeDead(node.ID)
			log.Printf("[FAILURE] Nodo %s marcato come DEAD (non visto da %v)", node.ID, timeSinceLastSeen)
		}

		// Rimuovi nodi DEAD dopo 120 secondi (pulizia)
		if node.Status == "dead" && timeSinceLastSeen > 120*time.Second {
			localMembership.RemoveNode(node.ID)
			log.Printf("[FAILURE] Nodo %s rimosso dalla Membership List (morto da %v)", node.ID, timeSinceLastSeen)
		}
	}
}
