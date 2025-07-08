package gossip

import (
	"encoding/json"
	"log"
	"math/rand"
	"net"
	"time"

	"Gossip/internal/join"
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

		// ✅ Prima determina il tipo di messaggio
		var messageType struct {
			Type string `json:"type"`
		}

		err = json.Unmarshal(buffer[:n], &messageType)
		if err != nil {
			log.Printf("[GOSSIP] Messaggio non valido ricevuto: %v", err)
			continue
		}

		// ✅ Gestisci in base al tipo di messaggio
		switch messageType.Type {
		case "leave":
			// ✅ Gestione messaggio LEAVE
			var leaveMsg util.LeaveMessage
			err = json.Unmarshal(buffer[:n], &leaveMsg)
			if err != nil {
				log.Printf("[GOSSIP] Errore parsing LEAVE: %v", err)
				continue
			}

			// Gestisci LEAVE direttamente qui
			leavingNodeID := leaveMsg.Sender
			log.Printf("[LEAVE] Ricevuto messaggio LEAVE da nodo %s", leavingNodeID)
			localMembership.RemoveNode(leavingNodeID)
			log.Printf("[LEAVE] Nodo %s rimosso dalla Membership List", leavingNodeID)

		case "join":
			// ✅ Gestione messaggio JOIN
			go join.HandleJoinRequest(buffer[:n], senderAddr, localMembership, selfNode)

		case "gossip_update", "join_ack":
			// ✅ Gestione messaggi Gossip normali
			var gossipMessage util.GossipMessage
			err = json.Unmarshal(buffer[:n], &gossipMessage)
			if err != nil {
				log.Printf("[GOSSIP] Errore parsing Gossip message: %v", err)
				continue
			}
			go HandleGossipMessage(gossipMessage, senderAddr, localMembership, selfNode)

		default:
			log.Printf("[GOSSIP] Tipo messaggio sconosciuto: %s da %s", messageType.Type, senderAddr)
		}
	}
}

func HandleLeaveMessage(leaveMsg util.LeaveMessage, senderAddr net.Addr, localMembership *membership.MembershipList) {
	leavingNodeID := leaveMsg.Sender
	log.Printf("[LEAVE] Ricevuto messaggio LEAVE da nodo %s", leavingNodeID)

	// Rimuovi il nodo dalla Membership List
	localMembership.RemoveNode(leavingNodeID)
	log.Printf("[LEAVE] Nodo %s rimosso dalla Membership List", leavingNodeID)
}

// ✅ Avvia il ciclo periodico di Gossip (Push-Pull + Heartbeat implicito)
func StartGossipCycle(nodeID, nodeIP, nodePort string, localMembership *membership.MembershipList, selfNode util.NodeStatus) {

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		<-ticker.C

		// ✅ AGGIORNA IL PROPRIO TIMESTAMP PRIMA DI TUTTO
		localMembership.UpdateLastSeen(selfNode.ID)

		// Seleziona peer casuali dalla Membership List (escludendo sé stesso e nodi morti)
		peers := localMembership.GetCopy()
		alivePeers := []util.NodeStatus{}

		// ✅ FILTRA: Solo nodi alive e suspect (esclude DEAD)
		for _, peer := range peers {
			if peer.ID != selfNode.ID && (peer.Status == "alive" || peer.Status == "suspect") {
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

		// ✅ SMART MEMBERSHIP: Include solo nodi non DEAD nel gossip
		allNodes := localMembership.GetCopy()
		activeMembership := []util.NodeStatus{}

		for _, node := range allNodes {
			// Include solo nodi che non sono DEAD
			if node.Status != "dead" {
				activeMembership = append(activeMembership, node)
			}
		}

		// ✅ Costruisce il Gossip Update con membership FILTRATA
		message := util.GossipMessage{
			Type:       "gossip_update",
			Sender:     selfNode,
			Membership: activeMembership, // Solo nodi attivi
		}

		// Invia Gossip Update al peer scelto
		addr := net.JoinHostPort(target.IP, target.Port)
		sendGossipMessage(addr, message)

		log.Printf("[GOSSIP] Gossip Update inviato a %s con %d nodi", target.ID, len(activeMembership))
	}
}

// ✅ Gestione del messaggio Gossip Update ricevuto
// ✅ Gestione completa dei messaggi ricevuti (Gossip Update, JOIN, LEAVE)
func HandleGossipMessage(message util.GossipMessage, senderAddr net.Addr, localMembership *membership.MembershipList, selfNode util.NodeStatus) {

	// ✅ Gestione messaggio LEAVE
	if message.Type == "leave" {
		leavingNodeID := message.Sender.ID
		log.Printf("[LEAVE] Ricevuto messaggio LEAVE da nodo %s", leavingNodeID)

		// Rimuovi il nodo dalla Membership List
		localMembership.RemoveNode(leavingNodeID)
		log.Printf("[LEAVE] Nodo %s rimosso dalla Membership List", leavingNodeID)
		return
	}

	// ✅ Gestione messaggio JOIN
	if message.Type == "join" {
		// Converti il messaggio a JoinMessage
		joinData, _ := json.Marshal(message)
		join.HandleJoinRequest(joinData, senderAddr, localMembership, selfNode)
		return
	}

	// ✅ Gestione Gossip Update normale (tipo "gossip_update" o "join_ack")
	if message.Type == "gossip_update" || message.Type == "join_ack" {
		log.Printf("[GOSSIP] Ricevuto %s da %s con %d nodi.\n", message.Type, message.Sender.ID, len(message.Membership))

		// Aggiorna la Membership List locale (merge)
		for _, node := range message.Membership {
			localMembership.AddOrUpdateNode(node)
		}

		// Aggiorna anche l'ultimo visto del mittente (heartbeat implicito)
		localMembership.UpdateLastSeen(message.Sender.ID)

		// ✅ Fase di Pull: rispondi solo se è un gossip_update normale (non join_ack)
		if message.Type == "gossip_update" {
			myMembership := localMembership.GetCopy()
			response := util.GossipMessage{
				Type:       "gossip_update",
				Sender:     selfNode,
				Membership: myMembership,
			}

			// Serializza e invia risposta al mittente
			sendGossipMessage(senderAddr.String(), response)
		}
		return
	}

	// ✅ Messaggio non riconosciuto
	log.Printf("[GOSSIP] Tipo messaggio non riconosciuto: %s", message.Type)
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
