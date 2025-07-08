package leave

import (
	"encoding/json"
	"log"
	"net"

	"Gossip/internal/membership"
	"Gossip/internal/util"
)

// ✅ Invia messaggio LEAVE a tutti i nodi conosciuti prima di disconnettersi
func SendLeaveMessage(localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	nodes := localMembership.GetCopy()

	// Crea il messaggio LEAVE
	leaveMessage := util.LeaveMessage{
		Type:   "leave",
		Sender: selfNode.ID,
	}

	log.Printf("[LEAVE] Invio messaggio LEAVE a %d nodi conosciuti.", len(nodes)-1)

	sentCount := 0
	for _, node := range nodes {
		// ✅ Invia a tutti i nodi (alive, suspect) tranne sé stesso
		if node.ID != selfNode.ID {
			// Invia anche a nodi SUSPECT perché potrebbero essere ancora raggiungibili
			if node.Status == "alive" || node.Status == "suspect" {
				err := sendLeaveToNode(node, leaveMessage)
				if err == nil {
					sentCount++
				}
			} else {
				log.Printf("[LEAVE] Skip nodo %s (status: %s)", node.ID, node.Status)
			}
		}
	}

	log.Printf("[LEAVE] Messaggi LEAVE inviati a %d nodi. Nodo pronto per disconnessione.", sentCount)
}

// ✅ Invia messaggio LEAVE a un singolo nodo
func sendLeaveToNode(targetNode util.NodeStatus, leaveMessage util.LeaveMessage) error {
	addr := net.JoinHostPort(targetNode.IP, targetNode.Port)

	// Connessione UDP
	conn, err := net.Dial("udp", addr)
	if err != nil {
		log.Printf("[LEAVE] Errore connessione a %s: %v", addr, err)
		return err
	}
	defer conn.Close()

	// Serializzazione messaggio
	data, err := json.Marshal(leaveMessage)
	if err != nil {
		log.Printf("[LEAVE] Errore serializzazione messaggio LEAVE: %v", err)
		return err
	}

	// Invio
	_, err = conn.Write(data)
	if err != nil {
		log.Printf("[LEAVE] Errore invio LEAVE a %s: %v", addr, err)
		return err
	}

	log.Printf("[LEAVE] Messaggio LEAVE inviato a %s", addr)
	return nil
}

// ✅ Gestisce la ricezione di un messaggio LEAVE da un altro nodo
// NOTA: Questa funzione non è più necessaria perché la gestione LEAVE
// è stata spostata direttamente nel server UDP di gossip.go
// La manteniamo per compatibilità ma non è chiamata
func HandleLeaveMessage(data []byte, addr net.Addr, localMembership *membership.MembershipList) {
	// Parsing del messaggio ricevuto
	var leaveMsg util.LeaveMessage
	err := json.Unmarshal(data, &leaveMsg)
	if err != nil {
		log.Printf("[LEAVE] Errore parsing messaggio LEAVE: %v", err)
		return
	}

	leavingNodeID := leaveMsg.Sender
	log.Printf("[LEAVE] Ricevuto messaggio LEAVE da nodo %s", leavingNodeID)

	// Rimuovi il nodo dalla Membership List
	localMembership.RemoveNode(leavingNodeID)
	log.Printf("[LEAVE] Nodo %s rimosso dalla Membership List", leavingNodeID)
}
