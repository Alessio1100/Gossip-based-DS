package gossip

import (
	"encoding/json"
	"log"
	"math/rand"
	"net"
	"time"

	"Gossip/internal/membership"
	"Gossip/internal/util"
)

// ✅ Avvia il server UDP per ricevere messaggi (Gossip, JOIN, LEAVE)
func StartUDPServer(port string, localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	addr := ":" + port
	conn, err := net.ListenPacket("udp", addr)
	if err != nil {
		log.Fatalf("[GOSSIP] Errore avvio server UDP: %v", err)
	}
	defer conn.Close()
	log.Printf("[GOSSIP] Server UDP in ascolto su %s\n", addr)

	buffer := make([]byte, 4096)

	for {
		n, senderAddr, err := conn.ReadFrom(buffer)
		if err != nil {
			log.Printf("[GOSSIP] Errore ricezione messaggio: %v", err)
			continue
		}

		// Parsing del messaggio ricevuto
		var message util.GossipMessage
		err = json.Unmarshal(buffer[:n], &message)
		if err != nil {
			log.Printf("[GOSSIP] Messaggio non valido ricevuto: %v", err)
			continue
		}

		// Gestione del messaggio ricevuto
		go HandleGossipMessage(message, senderAddr, localMembership, selfNode)
	}
}

// ✅ Avvia il ciclo periodico di Gossip (Push-Pull + Heartbeat implicito)
func StartGossipCycle(nodeID, nodeIP, nodePort string, localMembership *membership.MembershipList, selfNode util.NodeStatus) {

	ticker := time.NewTicker(20 * time.Second) // Frequenza configurabile del gossip
	defer ticker.Stop()

	for {
		<-ticker.C // Attesa del prossimo ciclo

		// Seleziona peer casuali dalla Membership List (escludendo sé stesso e nodi morti)
		peers := localMembership.GetCopy()
		alivePeers := []util.NodeStatus{}

		for _, peer := range peers {
			if peer.ID != nodeID && peer.Status == "alive" {
				alivePeers = append(alivePeers, peer)
			}
		}

		// Se non ci sono peer disponibili, skip ciclo
		if len(alivePeers) == 0 {
			log.Println("[GOSSIP] Nessun peer disponibile per Gossip.")
			continue
		}

		// ✅ Scelta realmente casuale del peer
		target := alivePeers[rand.Intn(len(alivePeers))]

		// Aggiorna proprio timestamp (heartbeat implicito)
		localMembership.UpdateLastSeen(nodeID)

		// Costruisce il Gossip Update
		membershipList := localMembership.GetCopy()
		message := util.GossipMessage{
			Type:       "gossip_update",
			Sender:     selfNode,
			Membership: membershipList,
		}

		// Invia Gossip Update al peer scelto
		addr := net.JoinHostPort(target.IP, target.Port)
		sendGossipMessage(addr, message)
	}
}

// ✅ Gestione del messaggio Gossip Update ricevuto
func HandleGossipMessage(message util.GossipMessage, senderAddr net.Addr, localMembership *membership.MembershipList, selfNode util.NodeStatus) {
	log.Printf("[GOSSIP] Ricevuto Gossip Update da %s con %d nodi.\n", message.Sender, len(message.Membership))

	// Aggiorna la Membership List locale (merge)
	for _, node := range message.Membership {
		localMembership.AddOrUpdateNode(node)
	}

	// Aggiorna anche l'ultimo visto del mittente (heartbeat implicito)
	localMembership.UpdateLastSeen(message.Sender.ID)

	// Fase di Pull: rispondi al mittente con la propria Membership List
	myMembership := localMembership.GetCopy()
	response := util.GossipMessage{
		Type:       "gossip_update",
		Sender:     selfNode,
		Membership: myMembership,
	}

	// Serializza e invia risposta al mittente
	sendGossipMessage(senderAddr.String(), response)
}

// ✅ Funzione per inviare un messaggio Gossip a un peer
func sendGossipMessage(addr string, message util.GossipMessage) {
	conn, err := net.Dial("udp", addr)
	if err != nil {
		log.Printf("[GOSSIP] Errore connessione UDP a %s: %v", addr, err)
		return
	}
	defer conn.Close()

	data, err := json.Marshal(message)
	if err != nil {
		log.Printf("[GOSSIP] Errore serializzazione messaggio: %v", err)
		return
	}

	_, err = conn.Write(data)
	if err != nil {
		log.Printf("[GOSSIP] Errore invio messaggio Gossip a %s: %v", addr, err)
	}
}
