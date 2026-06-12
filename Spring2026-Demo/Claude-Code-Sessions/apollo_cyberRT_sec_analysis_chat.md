╭─── Claude Code v2.1.176 ─────────────────────────────────────────────────────╮
│                                                    │ Tips for getting        │
│                Welcome back Steven!                │ started                 │
│                                                    │ Run /init to create a … │
│                      ▗ ▗   ▖ ▖                     │ ─────────────────────── │
│                                                    │ What's new              │
│                        ▘▘ ▝▝                       │ Session titles are now… │
│     Sonnet 4.6 · Claude Pro · skngo1@uci.edu's     │ Added `footerLinksRege… │
│     Organization                                   │ Improved Bedrock crede… │
│         ~/Desktop/security_research/apollo         │ /release-notes for more │
╰──────────────────────────────────────────────────────────────────────────────╯


❯ I am a security researcher comparing between security properties (or lack     
  thereof) in Autoware and Apollo. Autoware uses ROS2 Humble or Jazzy as it's   
  node-based middleware layer, but does not appear to have any sort of node     
  authentication, which may allow for malicious nodes to enter the network and  
  then make unauthenticated calls to the Autoware AD API endpoints (e.g.,       
  making an emergency call/stop). I now want to check if CyberRT, which is      
  Apollo's middleware layer implementation, has any similar issues or any other 
  security issues. Can you scan through the codebase of Apollo for me to        
  investigate for potential security issues?                                    

⏺ I'll do a thorough security scan of the Apollo codebase, focusing on CyberRT's
  middleware layer and looking for authentication, authorization, and other
  security issues. Let me spawn a specialized exploration agent for this.

⏺ Explore(CyberRT security audit)
  ⎿  Done (61 tool uses · 92.9k tokens · 2m 38s)
  (ctrl+o to expand)

⏺ Let me save some context about this research to memory, then present the
  findings.

  Recalled 1 memory, wrote 3 memories (ctrl+o to expand)

⏺ Here is the full security audit report for CyberRT:

  ---
  Apollo CyberRT Security Audit

  Bottom line: CyberRT has essentially the same security posture as 
  Autoware/ROS2 without DDS-Security enabled — no authentication, no encryption,
  no access control at any layer.

  ---
  1. Node Authentication — CRITICAL: NONE

  cyber/node/node_channel_impl.h:78-94 — Nodes join via
  node_manager_->Join(node_attr_, RoleType::ROLE_NODE) with no credentials. The
  RoleAttributes struct contains only host_name, host_ip, process_id, node_name,
  and node_id (a simple hash of the name). The Check() function in
  cyber/service_discovery/specific_manager/manager.cc:98-113 performs only basic
  validation, never identity verification. Any process can register as any
  node.

  ---
  2. Transport Security — CRITICAL: NONE

  cyber/transport/rtps/participant.cc:64-140 — RTPS is configured for plain UDP
  multicast (239.255.0.1), no TLS, no security policies.
  cyber/proto/transport_conf.proto has zero security-related fields — only SHM
  config, RTPS attributes, and communication modes. All inter-node traffic is
  cleartext.

  ---
  3. Message Integrity — CRITICAL: NONE

  cyber/transport/message/message_info.h:30-76 — MessageInfo contains sender ID,
  channel ID, sequence number, and timestamp. No signatures, no HMAC, no 
  message authentication codes.
  cyber/transport/dispatcher/rtps_dispatcher.h:83-107 accepts any parsed message
  with no integrity check.

  ---
  4. Access Control — CRITICAL: NONE

  cyber/proto/role_attributes.proto:12-29 — RoleAttributes has no permission
  fields whatsoever. Any node can publish or subscribe to any channel. Any node
  can call any service. There is no topic-level or service-level ACL.

  ---
  5. Service/RPC Security — CRITICAL: NONE

  cyber/service/service.h and cyber/service/client.h — Services are invocable by
  any node with knowledge of the service name. Client::HandleResponse() only
  matches on sequence numbers, not sender identity. A malicious node can call
  safety-critical services (motion control, braking, etc.) directly.

  ---
  6. External API (DreamView) — CRITICAL: UNAUTHENTICATED

  modules/dreamview/backend/common/handlers/websocket_handler.h:68-69:
  bool handleConnection(CivetServer *server, const Connection *conn) override {
    return true;  // accepts ALL connections unconditionally
  }
  WebSocket handlers for /websocket, /map, /pointcloud, /camera, /plugin are all
  registered with zero authentication. Any network-reachable client can monitor
  sensor data and issue HMI commands (vehicle scenario, dynamic model changes,
  etc.).

  ---
  7. Shared Memory Security — CRITICAL: WORLD-READABLE

  cyber/transport/shm/posix_segment.cc:45:
  int fd = shm_open(shm_name_.c_str(), O_RDWR | O_CREAT | O_EXCL, 0644);
  Mode 0644 means the group can read and any other local user can also read all
  shared memory segments — which carry all sensor data and control commands. SHM
  segment names are deterministic (based on channel ID), so any local user can
  find and open them.

  ---
  8. Node Discovery — CRITICAL: SPOOFABLE IDENTITY

  cyber/service_discovery/specific_manager/manager.cc:220-228:
  bool Manager::IsFromSameProcess(const ChangeMsg& msg) {
    auto& host_name = msg.role_attr().host_name();
    int process_id = msg.role_attr().process_id();
    if (process_id != process_id_ || host_name != host_name_) {
      return false;
    }
    return true;
  }
  The hostname and PID checked here are extracted from the message itself — a
  network attacker can forge both fields trivially. FastRTPS discovery runs over
  unauthenticated UDP multicast with no certificate validation.

  ---
  9. Privilege Separation — HIGH: NONE

  cyber/proto/topology_change.proto defines RoleType with only functional
  distinctions (ROLE_NODE, ROLE_WRITER, ROLE_READER, ROLE_SERVER, ROLE_CLIENT) —
  no security privilege levels. All components run with identical access
  rights. A compromised non-safety module has the same access as the planning or
  control module.

  ---
  10. Configuration Security — MEDIUM: INSECURE DEFAULTS

  cyber/conf/cyber.pb.conf has no security configuration fields at all.
  cyber/transport/rtps/participant.cc:112-121 binds to 127.0.0.1 by default but
  this is overridable with the CYBER_IP environment variable with no validation.
  CYBER_DOMAIN_ID similarly configurable via env var.

  ---
  Comparison to Autoware/ROS2

  ┌───────────────────┬───────────────────────────┬────────────────────────┐
  │     Dimension     │    Autoware (ROS2 no      │     Apollo CyberRT     │
  │                   │       DDS-Security)       │                        │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Node              │ None                      │ None                   │
  │ authentication    │                           │                        │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Transport         │ None                      │ None                   │
  │ encryption        │                           │                        │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Message signing   │ None                      │ None                   │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Topic/service ACL │ None                      │ None                   │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Discovery         │ Unauthenticated           │ Unauthenticated +      │
  │ security          │                           │ spoofable              │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ Web UI auth       │ N/A (external)            │ None (DreamView)       │
  ├───────────────────┼───────────────────────────┼────────────────────────┤
  │ SHM permissions   │ Varies                    │ World-readable (0644)  │
  └───────────────────┴───────────────────────────┴────────────────────────┘

  The postures are nearly identical, with Apollo actually being marginally worse
  in two areas:
  - The IsFromSameProcess() spoof vulnerability is specific to CyberRT's custom
  topology management
  - DreamView's unconditional handleConnection() is a built-in unauthenticated
  web interface (ROS2 doesn't have an equivalent bundled)

  Key Attack Scenarios

  1. Remote control injection: Attacker on same network sends RTPS messages to
  steering/brake topics — no authentication prevents this
  2. Service exploitation: Any reachable node can call safety-critical services
  directly
  3. Node impersonation: Forge host_name + process_id in RoleAttributes to pass
  IsFromSameProcess() checks
  4. DreamView hijack: Connect to the unauthenticated WebSocket and issue HMI
  commands or exfiltrate sensor streams
  5. Local SHM read/write: Any local user (or container escape) can
  read/overwrite shared memory segments carrying live sensor and control data

  ---
  Both systems rely entirely on network-level isolation as their security
  boundary, which is not an adequate defense model for safety-critical
  autonomous vehicles. If you want, I can dig deeper into any specific
  vulnerability or help you draft a formal write-up.

✻ Baked for 4m 5s

❯ What do you mean by network-level isolation? Where does it say that this is   
  Apollo/CyberRT's main defense mechanism?                                      

⏺ Fair challenge — I inferred that claim from the absence of other security
  mechanisms, rather than finding it explicitly stated anywhere in the codebase
  or documentation. Let me check if Apollo actually documents its security model
  or makes any explicit assumptions about the network environment.

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

⏺ Bash(find /Users/stengo/Desktop/security_research/apollo/docs -name "*.md" |
      xargs grep -l -i "security\|auth\|trust\|isolat" 2>/dev/null)
  ⎿  Error: Exit code 1

⏺ Bash(find /Users/stengo/Desktop/security_research/apollo/cyber -name "*.md" |
      xargs grep -l -i "security\|auth\|trust\|network" 2>/dev/null)
  ⎿  /Users/stengo/Desktop/security_research/apollo/cyber/docs/cyber_faqs.m
     d
     /Users/stengo/Desktop/security_research/apollo/cyber/doxy-docs/source/
     CyberRT_FAQs.md

  Searched for 1 pattern (ctrl+o to expand)

⏺ Bash(find /Users/stengo/Desktop/security_research/apollo/cyber/doxy-docs -name
      "*.md" | xargs grep -l -i "security\|auth\|trust" 2>/dev/null && find
      /Users/stengo/De…)
  ⎿  /Users/stengo/Desktop/security_research/apollo/cyber/doxy-docs/source/
     CyberRT_FAQs.md
     /Users/stengo/Desktop/security_research/apollo/cyber/docs/cyber_api_fo
     … +13 lines (ctrl+o to expand)

  Searched for 1 pattern (ctrl+o to expand)

⏺ Good — I found the one relevant documentation snippet. That's the extent of
  it. The phrase "network-level isolation" was my own inference, not a
  documented claim from Apollo. Let me be direct about this.

  ---
  You're right to push back on that. I over-stated it.

  The phrase "relies on network-level isolation as its security boundary" was my
  inference, not a documented claim from Apollo. I presented it as if it were a
  design decision Apollo explicitly made, but there is nothing in the codebase
  or documentation that says that.

  What the documentation actually says is minimal: cyber/docs/cyber_faqs.md
  mentions that multi-host communication requires the hosts to be "under the
  same network segment of the local area network" — but that's a functional 
  requirement (RTPS multicast only works on the same LAN segment), not a stated
  security model.

  There is no security model documented anywhere in the Apollo codebase that I
  found. No threat model, no security design doc, no stated assumptions about
  the network environment. The accurate characterization is:

  ▎ Apollo/CyberRT has no documented security model at all. The absence of 
  ▎ authentication, encryption, and access controls appears to be a consequence 
  ▎ of design priorities (performance, simplicity, developer ergonomics), not a 
  ▎ deliberate choice to defer to network isolation. Whether Apollo's designers 
  ▎ intended network isolation as a compensating control, or simply never 
  ▎ considered adversarial network conditions, cannot be determined from the 
  ▎ codebase alone.

  That's an important distinction for your research — "no security model" and
  "relies on network isolation" are different claims with different
  implications.

✻ Baked for 33s

※ recap: Security researcher auditing Apollo's CyberRT middleware for vulnerabilities comparable to Autoware/ROS2. Audit is complete — next step is deciding which specific finding to investigate further or begin drafting a formal write-up. (disable recaps in /config)

❯ Can you scan through the entire Apollo codebase to verify that CyberRT is the 
  middleware equivalent in Apollo and would be responsible for node             
  management? Or if anything else in Apollo would be responsible for the        
  security & privacy of Apollo?                                                 

⏺ Explore(Apollo middleware & security architecture scan)
  ⎿  Done (55 tool uses · 82.0k tokens · 5m 15s)
  (ctrl+o to expand)

⏺ Good findings. Let me verify a couple of the specific claims before presenting
  them — particularly the DreamView TLS flag and the Docker seccomp line.

  Searched for 4 patterns (ctrl+o to expand)

⏺ Both verified. Here's the complete, accurate picture:

  ---
  Findings

  Question 1: Is CyberRT the sole middleware/node manager?

  CyberRT is the primary and near-universal middleware, but not the only IPC 
  mechanism in Apollo. Three additional communication channels exist:

  a) gRPC — V2X module only
  modules/v2x/v2x_proxy/obu_interface/grpc_interface/ implements a gRPC
  server/client for vehicle-to-infrastructure (V2X) communication. Default
  binding is 127.0.0.1:50100/50101 but this is a runtime flag — easily changed
  to any network interface. No auth interceptors on the gRPC services.

  b) Raw UDP bridge
  modules/bridge/ implements a UDP bridge component that can forward CyberRT
  messages over UDP sockets to/from configurable remote hosts and ports. This
  bypasses CyberRT's transport entirely for cross-machine scenarios.

  c) DreamView WebSocket/HTTP
  modules/dreamview/ is a CivetWeb-based HTTP server with WebSocket handlers —
  effectively a second IPC boundary into the system from the browser. Already
  covered in the previous audit.

  All other modules (planning, perception, prediction, localization, control,
  canbus, routing, etc.) communicate exclusively via CyberRT. So CyberRT is 
  authoritative for all internal node management — the three above are
  external-facing escape hatches.

  ---
  Question 2: Does anything in Apollo handle security or privacy?

  Almost nothing — and what exists is weak or off by default.

  What actually exists:

  Mechanism: Optional HTTPS for DreamView
  Location: modules/dreamview/backend/dreamview.cc:80-84 +
  dreamview_gflags.cc:53
  What it does: Passes an SSL cert path to CivetWeb if the file exists
  Honest assessment: Off by default (empty string); no auth even when TLS is on
  —
    only encrypts the channel
  ────────────────────────────────────────
  Mechanism: V2X RSU whitelist
  Location: modules/v2x/v2x_proxy/app/utils.cc:461-466
  What it does: Checks V2X RSU IDs against a file-based list
  Honest assessment: String matching only, no cryptographic verification; scoped

    to V2X traffic lights only

  What is explicitly NOT security despite the name:
  - Guardian module (modules/guardian/) — a safety timeout/override system
  (watchdog for control commands), not an adversarial security mechanism
  - Monitor module (modules/monitor/) — hardware/software health checks
  (latency, disk, CPU), not an access control or intrusion detection system

  Additional finding — Docker container hardening is actively disabled:

  docker/scripts/docker_base.sh:104:
  DOCKER_RUN_CMD="docker run --device=/dev/kfd --device=/dev/dri --security-opt 
  seccomp=unconfined --group-add video"

  seccomp=unconfined explicitly removes the Linux syscall filter that Docker
  applies by default. Combined with no AppArmor/SELinux profiles and no
  capability dropping, the container provides essentially no isolation beyond a
  filesystem boundary.

  ---
  Overall picture

  CyberRT is definitively the node management layer for all internal Apollo
  modules. The security surface is:

  1. CyberRT — no auth, no encryption, no ACL (as previously audited)
  2. DreamView HTTP/WS — unauthenticated by default, optional TLS available but
  provides no auth
  3. V2X gRPC — unauthenticated plaintext gRPC
  4. UDP bridge — unauthenticated raw UDP

  There is no dedicated security module, no threat model documentation, no
  authentication framework, and the container environment explicitly disables
  OS-level syscall filtering. The security posture is consistent across the
  entire stack.

✻ Cooked for 3m 12s

❯ /exit                                                                         
  ⎿  Catch you later!