package util

// ✅ Struttura che rappresenta lo stato di un nodo nella rete
type NodeStatus struct {
	ID       string `json:"id"`        // Identificativo univoco del nodo (es. "node1")
	IP       string `json:"ip"`        // Indirizzo IP del nodo
	Port     string `json:"port"`      // Porta su cui il nodo ascolta
	Status   string `json:"status"`    // Stato del nodo: alive, suspect, dead
	LastSeen string `json:"last_seen"` // Timestamp dell'ultima volta visto (RFC3339)
}

// ✅ Messaggio utilizzato per Gossip Update, JOIN_ACK, ecc.
type GossipMessage struct {
	Type       string       `json:"type"`
	Sender     NodeStatus   `json:"sender"`
	Membership []NodeStatus `json:"membership,omitempty"`
}

// ✅ Messaggio di JOIN (richiesta di entrare nella rete)
type JoinMessage struct {
	Type   string     `json:"type"`   // Tipo del messaggio: "join"
	Sender NodeStatus `json:"sender"` // Informazioni del nodo che vuole entrare (NodeStatus)
}

// ✅ Messaggio di LEAVE (richiesta di uscire dalla rete)
type LeaveMessage struct {
	Type   string `json:"type"`   // Tipo del messaggio: "leave"
	Sender string `json:"sender"` // ID del nodo che vuole lasciare la rete (stringa, perché basta ID)
}
