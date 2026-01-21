# CockroachDB Installer Flow Diagrams

## 1. Overview Architecture

```mermaid
flowchart TB
    subgraph Client["🖥️ Client Applications"]
        App[Application]
    end

    subgraph LB["⚖️ Load Balancer Server"]
        HAProxy[HAProxy<br/>Port: 26257]
        PgBouncer[PgBouncer<br/>Port: 6432]
    end

    subgraph Cluster["🗄️ CockroachDB Cluster"]
        Node1[Node 1<br/>SQL: 26257<br/>UI: 8080]
        Node2[Node 2<br/>SQL: 26257<br/>UI: 8080]
        Node3[Node 3<br/>SQL: 26257<br/>UI: 8080]
    end

    App -->|High Concurrency| PgBouncer
    App -->|Direct| HAProxy
    PgBouncer --> HAProxy
    HAProxy -->|Round Robin| Node1
    HAProxy -->|Round Robin| Node2
    HAProxy -->|Round Robin| Node3
    Node1 <-->|Raft Consensus| Node2
    Node2 <-->|Raft Consensus| Node3
    Node3 <-->|Raft Consensus| Node1
```

## 2. Complete Installation Flow

```mermaid
flowchart TD
    Start([🚀 Start Installation]) --> Clone[Clone Repository]
    Clone --> InfraDecision{Deployment Type?}

    InfraDecision -->|Single Site| SingleSite[3 Node Cluster]
    InfraDecision -->|Multi Site DR| MultiSite[2+3 Topology]

    %% Single Site Flow
    SingleSite --> ProvisionSingle[Provision Infrastructure<br/>• 3x CockroachDB Nodes<br/>• 1x Load Balancer]
    ProvisionSingle --> SetupNodes

    %% Multi Site Flow
    MultiSite --> ProvisionMulti[Provision Infrastructure<br/>• Site A: 2 Nodes + LB<br/>• Site B: 3 Nodes + LB]
    ProvisionMulti --> SetupNodes

    %% Common Node Setup
    subgraph SetupNodes["📦 Setup Each CockroachDB Node"]
        direction TB
        TransferScripts[Transfer Scripts via SCP]
        TransferScripts --> RunSetupOS[Run setup_os.sh]
        RunSetupOS --> RunSetupCockroach[Run setup_cockroach.sh]
        RunSetupCockroach --> ConfigService[Configure systemd Service]
        ConfigService --> StartNode[Start & Enable Service]
    end

    SetupNodes --> InitCluster[Initialize Cluster<br/>cockroach init]
    InitCluster --> SetupLB

    %% Load Balancer Setup
    subgraph SetupLB["⚖️ Setup Load Balancer"]
        direction TB
        RunLBOS[Run setup_loadbalancer_os.sh]
        RunLBOS --> RunHAProxy[Run setup_haproxy.sh]
        RunHAProxy --> NeedPooling{Need Connection<br/>Pooling?}
        NeedPooling -->|Yes >1000 conn| RunPgBouncer[Run setup_pgbouncer.sh]
        NeedPooling -->|No| SkipPgBouncer[Skip PgBouncer]
    end

    SetupLB --> SetupBackup

    %% Backup Setup
    subgraph SetupBackup["💾 Setup Backup Automation"]
        direction TB
        RunBackupSetup[Run setup_backup_automation.sh]
        RunBackupSetup --> SelectSchedule{Select Schedule}
        SelectSchedule -->|Daily 2AM| DailyBackup[Configure Daily Cron]
        SelectSchedule -->|Daily + Hourly| HourlyBackup[Configure Hourly Incremental]
        SelectSchedule -->|Every 6 Hours| SixHour[Configure 6-Hour Cron]
        SelectSchedule -->|Custom| CustomCron[Configure Custom Schedule]
    end

    SetupBackup --> Verify

    %% Verification
    subgraph Verify["✅ Verification & Testing"]
        direction TB
        TestSQL[Test SQL Connection]
        TestSQL --> TestHA[Test HAProxy Stats]
        TestHA --> TestCluster[Verify Cluster Status]
        TestCluster --> TestBackup[Test Backup/Restore]
    end

    Verify --> End([🎉 Cluster Ready])
```

## 3. OS Optimization Flow (setup_os.sh)

```mermaid
flowchart TD
    Start([Start setup_os.sh]) --> DetectOS{Detect OS}

    DetectOS -->|Ubuntu/Debian| APT[Use apt-get]
    DetectOS -->|RHEL/Rocky/Alma| YUM[Use yum/dnf]
    DetectOS -->|Other| Warn[Warning: Unsupported]

    APT --> DetectArch
    YUM --> DetectArch
    Warn --> DetectArch

    DetectArch{Detect Architecture}
    DetectArch -->|x86_64| AMD64[AMD64 Binary]
    DetectArch -->|aarch64| ARM64[ARM64 Binary]

    AMD64 --> CheckRAM
    ARM64 --> CheckRAM

    CheckRAM{Check RAM Size}
    CheckRAM -->|< 4GB| LowProfile["LOW Profile<br/>somaxconn=1024<br/>file-max=500000"]
    CheckRAM -->|4-16GB| MedProfile["MEDIUM Profile<br/>somaxconn=4096<br/>file-max=1000000"]
    CheckRAM -->|> 16GB| HighProfile["HIGH Profile<br/>somaxconn=8192<br/>file-max=2000000"]

    LowProfile --> CreateUser
    MedProfile --> CreateUser
    HighProfile --> CreateUser

    CreateUser[Create cockroach User]
    CreateUser --> ConfigLimits[Configure File Limits<br/>/etc/security/limits.d/]
    ConfigLimits --> ConfigSysctl[Configure Kernel Params<br/>/etc/sysctl.d/99-cockroach.conf]
    ConfigSysctl --> ConfigTHP[Configure THP: madvise]
    ConfigTHP --> DisableSwap[Disable Swap]
    DisableSwap --> ConfigFirewall[Configure Firewall<br/>Ports: 26257, 8080]
    ConfigFirewall --> SetTimezone[Set Timezone]
    SetTimezone --> End([OS Optimized ✓])
```

## 4. CockroachDB Installation Flow (setup_cockroach.sh)

```mermaid
flowchart TD
    Start([Start setup_cockroach.sh]) --> DetectArch{Detect Architecture}

    DetectArch -->|x86_64| AMD["Download linux-amd64<br/>v23.1.11"]
    DetectArch -->|aarch64| ARM["Download linux-arm64<br/>v23.1.11"]

    AMD --> CalcMem
    ARM --> CalcMem

    CalcMem[Calculate Memory Settings]
    CalcMem --> Cache["Cache = 25% RAM"]
    CalcMem --> SQLMem["SQL Memory = 25% RAM"]

    Cache --> InputConfig
    SQLMem --> InputConfig

    InputConfig[/Interactive Input:<br/>Node IP, Join Addresses/]
    InputConfig --> Download[Download CockroachDB Binary]
    Download --> Extract[Extract to /usr/local/bin]
    Extract --> CreateUser{User Exists?}

    CreateUser -->|No| AddUser[Create cockroach User]
    CreateUser -->|Yes| SkipUser[Skip User Creation]

    AddUser --> CreateDirs
    SkipUser --> CreateDirs

    CreateDirs[Create Directories<br/>/var/lib/cockroach<br/>/var/log/cockroach]
    CreateDirs --> SetPerms[Set Ownership & Permissions]
    SetPerms --> GenService[Generate systemd Service]

    GenService --> ServiceContent["cockroach.service<br/>--cache=XXXMiB<br/>--max-sql-memory=XXXMiB<br/>--join=IP1,IP2,IP3"]

    ServiceContent --> EnableService[Enable & Start Service]
    EnableService --> End([CockroachDB Installed ✓])
```

## 5. HAProxy Setup Flow (setup_haproxy.sh)

```mermaid
flowchart TD
    Start([Start setup_haproxy.sh]) --> DetectSpecs[Detect Server Specs]

    DetectSpecs --> CalcConn{Calculate Max Connections}
    CalcConn --> Formula["maxconn = min(RAM_MB / 2, 50000)"]

    Formula --> CalcTimeout{Calculate Timeouts}
    CalcTimeout -->|< 2GB| T30["timeout = 30s"]
    CalcTimeout -->|2-4GB| T60["timeout = 1m"]
    CalcTimeout -->|4-8GB| T120["timeout = 2m"]
    CalcTimeout -->|> 8GB| T300["timeout = 5m"]

    T30 --> InputNodes
    T60 --> InputNodes
    T120 --> InputNodes
    T300 --> InputNodes

    InputNodes[/Input CockroachDB<br/>Node IPs/]
    InputNodes --> InputAuth{Enable Stats Auth?}

    InputAuth -->|Yes| SetAuth[Set Username/Password]
    InputAuth -->|No| NoAuth[Skip Authentication]

    SetAuth --> GenConfig
    NoAuth --> GenConfig

    GenConfig[Generate haproxy.cfg]

    subgraph Config["HAProxy Configuration"]
        direction TB
        Global["global<br/>maxconn, nbthread, bufsize"]
        Defaults["defaults<br/>mode tcp, timeouts"]
        Frontend["frontend postgresql<br/>bind *:26257"]
        Backend["backend cockroachdb<br/>balance roundrobin<br/>health check: tcp"]
        Stats["listen stats<br/>bind *:8081"]
    end

    GenConfig --> Config
    Config --> Verify[Verify Configuration]
    Verify --> Restart[Restart HAProxy Service]
    Restart --> End([HAProxy Ready ✓])
```

## 6. PgBouncer Setup Flow (setup_pgbouncer.sh)

```mermaid
flowchart TD
    Start([Start setup_pgbouncer.sh]) --> DetectOS[Detect OS]
    DetectOS --> Install[Install PgBouncer Package]

    Install --> CheckRAM{Check RAM Size}
    CheckRAM -->|< 1GB| Conn500["max_client = 500<br/>⚠️ Not Recommended"]
    CheckRAM -->|1-2GB| Conn2000["max_client = 2000"]
    CheckRAM -->|2-4GB| Conn5000["max_client = 5000"]
    CheckRAM -->|4-8GB| Conn10000["max_client = 10000"]
    CheckRAM -->|> 8GB| Conn20000["max_client = 20000"]

    Conn500 --> InputConfig
    Conn2000 --> InputConfig
    Conn5000 --> InputConfig
    Conn10000 --> InputConfig
    Conn20000 --> InputConfig

    InputConfig[/Interactive Input/]

    subgraph Inputs["Configuration Inputs"]
        direction TB
        I1[HAProxy IP Address]
        I2[Database Name]
        I3[Username & Password]
        I4[Total vCPU Count]
        I5["Pool Size = vCPU × 4"]
    end

    InputConfig --> Inputs
    Inputs --> GenIni[Generate pgbouncer.ini]

    subgraph IniConfig["pgbouncer.ini"]
        direction TB
        DB["[databases]<br/>db = host=haproxy port=26257"]
        PG["[pgbouncer]<br/>pool_mode = transaction<br/>max_client_conn = X<br/>default_pool_size = Y"]
    end

    GenIni --> IniConfig
    IniConfig --> GenAuth[Generate userlist.txt]
    GenAuth --> CreateService[Create systemd Service]
    CreateService --> StartService[Start & Enable Service]
    StartService --> End([PgBouncer Ready ✓])
```

## 7. Backup & Restore Flow

```mermaid
flowchart TD
    subgraph Backup["💾 Backup Flow (backup_cockroach.sh)"]
        direction TB
        B_Start([Start Backup]) --> B_Connect[Connect to CockroachDB]
        B_Connect --> B_Check{Last Backup Age?}
        B_Check -->|> 7 days or None| B_Full[FULL Backup]
        B_Check -->|< 7 days| B_Incr[INCREMENTAL Backup]
        B_Full --> B_Execute[Execute BACKUP SQL]
        B_Incr --> B_Execute
        B_Execute --> B_Verify[Verify with SHOW BACKUP]
        B_Verify --> B_Retention[Apply 30-day Retention]
        B_Retention --> B_Log[Log to backup.log]
        B_Log --> B_End([Backup Complete ✓])
    end

    subgraph Restore["🔄 Restore Flow (restore_cockroach.sh)"]
        direction TB
        R_Start([Start Restore]) --> R_Args[Parse Arguments]
        R_Args --> R_Mode{Restore Mode?}
        R_Mode -->|new| R_New["Create new_db_restored_timestamp"]
        R_Mode -->|replace| R_Replace["Drop & Recreate Original"]
        R_Mode -->|point-in-time| R_PIT["Restore to Timestamp"]
        R_New --> R_Execute[Execute RESTORE SQL]
        R_Replace --> R_Confirm{Confirm?}
        R_Confirm -->|Yes| R_Execute
        R_Confirm -->|No| R_Cancel([Cancelled])
        R_PIT --> R_InputTS[/Input Timestamp/]
        R_InputTS --> R_Execute
        R_Execute --> R_Verify[Verify Table Count]
        R_Verify --> R_Log[Log to restore.log]
        R_Log --> R_End([Restore Complete ✓])
    end

    subgraph Automation["⏰ Backup Automation (setup_backup_automation.sh)"]
        direction TB
        A_Start([Setup Automation]) --> A_Schedule{Select Schedule}
        A_Schedule -->|1| A_Daily["Daily at 2 AM"]
        A_Schedule -->|2| A_Hourly["Daily + Hourly Incremental"]
        A_Schedule -->|3| A_Six["Every 6 Hours"]
        A_Schedule -->|4| A_Custom[/"Custom Cron Expression"/]
        A_Daily --> A_Cron[Configure Cron Jobs]
        A_Hourly --> A_Cron
        A_Six --> A_Cron
        A_Custom --> A_Cron
        A_Cron --> A_Initial{Run Initial Backup?}
        A_Initial -->|Yes| A_RunNow[Execute Backup Now]
        A_Initial -->|No| A_Skip[Skip]
        A_RunNow --> A_End([Automation Configured ✓])
        A_Skip --> A_End
    end
```

## 8. Multi-Site DR Architecture (2+3 Topology)

```mermaid
flowchart TB
    subgraph SiteA["🏢 Site A (Primary)"]
        direction TB
        A_Node1["Node 1<br/>locality=site=a,rack=1<br/>Full Replica"]
        A_Node2["Node 2<br/>locality=site=a,rack=2<br/>Full Replica"]
        A_LB["HAProxy (Primary)<br/>:26257"]
        A_Node1 <--> A_Node2
    end

    subgraph SiteB["🏢 Site B (DR - Always On)"]
        direction TB
        B_Node3["Node 3<br/>locality=site=b,rack=1<br/>Full Replica"]
        B_Node4["Node 4<br/>locality=site=b,rack=2<br/>Full Replica"]
        B_Node5["Node 5<br/>locality=site=b,rack=3<br/>Witness (Voting Only)"]
        B_LB["HAProxy (Standby)<br/>:26257"]
        B_Node3 <--> B_Node4
        B_Node4 <--> B_Node5
        B_Node3 <--> B_Node5
    end

    App[Application]
    App -->|Primary Path| A_LB
    App -.->|Failover Path| B_LB
    A_LB --> A_Node1
    A_LB --> A_Node2
    B_LB --> B_Node3
    B_LB --> B_Node4

    A_Node1 <-->|Raft Replication| B_Node3
    A_Node2 <-->|Raft Replication| B_Node4
    A_Node1 <-->|Raft Replication| B_Node5
    A_Node2 <-->|Raft Replication| B_Node3

    subgraph Quorum["Quorum: 3/5 Nodes Required"]
        direction LR
        Q1["Normal: All 5 nodes ✓"]
        Q2["Site A Down: 3 nodes (Site B) ✓"]
        Q3["2 Nodes Down: 3 nodes ✓"]
        Q4["3+ Nodes Down: ✗ No Quorum"]
    end
```

## 8.1 Multi-Site Deployment Flow (2+3 Topology)

```mermaid
flowchart TD
    Start([🚀 Start Multi-Site Deployment]) --> Provision

    subgraph Provision["1️⃣ Provision Infrastructure"]
        direction TB
        P_SiteA["Site A (Primary)<br/>• Node 1: 2GB RAM, 2 CPU<br/>• Node 2: 2GB RAM, 2 CPU<br/>• HAProxy: 1GB RAM"]
        P_SiteB["Site B (DR)<br/>• Node 3: 2GB RAM, 2 CPU<br/>• Node 4: 2GB RAM, 2 CPU<br/>• Node 5 (Witness): 1GB RAM<br/>• HAProxy: 1GB RAM"]
    end

    Provision --> SetupSiteA

    subgraph SetupSiteA["2️⃣ Setup Site A Nodes"]
        direction TB
        A1_OS["Node 1: setup_os.sh"] --> A1_CRDB["Node 1: setup_cockroach.sh"]
        A2_OS["Node 2: setup_os.sh"] --> A2_CRDB["Node 2: setup_cockroach.sh"]
        A1_CRDB --> A1_Locality["Add locality flag:<br/>--locality=site=a,rack=1"]
        A2_CRDB --> A2_Locality["Add locality flag:<br/>--locality=site=a,rack=2"]
    end

    SetupSiteA --> SetupSiteB

    subgraph SetupSiteB["3️⃣ Setup Site B Nodes"]
        direction TB
        B3_OS["Node 3: setup_os.sh"] --> B3_CRDB["Node 3: setup_cockroach.sh"]
        B4_OS["Node 4: setup_os.sh"] --> B4_CRDB["Node 4: setup_cockroach.sh"]
        B5_OS["Node 5: setup_os.sh"] --> B5_CRDB["Node 5: setup_cockroach.sh"]
        B3_CRDB --> B3_Locality["--locality=site=b,rack=1"]
        B4_CRDB --> B4_Locality["--locality=site=b,rack=2"]
        B5_CRDB --> B5_Locality["--locality=site=b,rack=3<br/>(Witness Node)"]
    end

    SetupSiteB --> InitCluster["4️⃣ Initialize Cluster<br/>cockroach init --host=node1"]
    InitCluster --> ConfigZone

    subgraph ConfigZone["5️⃣ Configure Zone Replication"]
        direction TB
        Z1["Connect to cluster"]
        Z1 --> Z2["ALTER DATABASE defaultdb<br/>CONFIGURE ZONE USING<br/>num_replicas = 3"]
        Z2 --> Z3["Set constraints:<br/>Site A: 2 replicas<br/>Site B: 1 replica"]
        Z3 --> Z4["Set lease_preferences:<br/>Prefer Site A for writes"]
    end

    ConfigZone --> SetupLBs

    subgraph SetupLBs["6️⃣ Setup Load Balancers"]
        direction TB
        LB_A["Site A HAProxy<br/>Backend: Node 1, 2<br/>Backup: Node 3, 4"]
        LB_B["Site B HAProxy<br/>Backend: Node 3, 4<br/>Backup: Node 1, 2"]
    end

    SetupLBs --> Validate

    subgraph Validate["7️⃣ Validate Multi-Site"]
        direction TB
        V1["Check node localities"]
        V1 --> V2["Verify zone config"]
        V2 --> V3["Test Site A failover"]
        V3 --> V4["Test recovery"]
    end

    Validate --> End([✅ Multi-Site DR Ready])
```

## 8.2 Zone Configuration Flow

```mermaid
flowchart TD
    Start([Configure Zone Replication]) --> Connect["Connect to CockroachDB<br/>cockroach sql --host=node1"]

    Connect --> CheckLocality["Verify Node Localities<br/>SELECT node_id, locality FROM crdb_internal.gossip_nodes"]

    CheckLocality --> HasLocality{All nodes have<br/>locality set?}
    HasLocality -->|No| FixLocality["Fix: Add --locality flag<br/>to systemd service"]
    HasLocality -->|Yes| ConfigDB

    FixLocality --> RestartNodes["Restart affected nodes"]
    RestartNodes --> CheckLocality

    subgraph ConfigDB["Configure Database Zone"]
        direction TB
        DB1["ALTER DATABASE defaultdb<br/>CONFIGURE ZONE USING"]
        DB1 --> DB2["num_replicas = 3"]
        DB2 --> DB3["constraints = '{<br/>  \"+site=a\": 2,<br/>  \"+site=b\": 1<br/>}'"]
        DB3 --> DB4["lease_preferences = '[[+site=a]]'"]
    end

    ConfigDB --> VerifyZone["SHOW ZONE CONFIGURATION<br/>FOR DATABASE defaultdb"]
    VerifyZone --> CheckRanges["Check range distribution<br/>SHOW RANGES FROM DATABASE"]

    CheckRanges --> Balanced{Replicas<br/>balanced?}
    Balanced -->|No| Wait["Wait for rebalancing<br/>(may take minutes)"]
    Balanced -->|Yes| End([Zone Configuration Complete ✓])
    Wait --> CheckRanges
```

## 8.3 Failover Scenarios

```mermaid
flowchart TD
    subgraph Normal["🟢 Normal Operation"]
        direction LR
        N_App[Application] --> N_LB_A[Site A HAProxy]
        N_LB_A --> N_N1[Node 1 ★ Leader]
        N_LB_A --> N_N2[Node 2]
        N_N1 -.->|Replicate| N_N3[Node 3]
        N_N1 -.->|Replicate| N_N4[Node 4]
        N_N1 -.->|Vote Only| N_N5[Node 5 Witness]
    end

    subgraph Failover["🔴 Site A Down - Auto Failover"]
        direction LR
        F_App[Application] --> F_LB_B[Site B HAProxy]
        F_N1[Node 1 ✗]
        F_N2[Node 2 ✗]
        F_LB_B --> F_N3[Node 3 ★ New Leader]
        F_LB_B --> F_N4[Node 4]
        F_N5[Node 5 Witness<br/>Voting Member]
    end

    subgraph Recovery["🟡 Site A Recovery"]
        direction LR
        R_App[Application] --> R_LB_A[Site A HAProxy]
        R_N1[Node 1<br/>Rejoining] -.->|Catch up| R_N3[Node 3]
        R_N2[Node 2<br/>Rejoining] -.->|Catch up| R_N4[Node 4]
        R_LB_A --> R_N3
        R_LB_A --> R_N4
    end

    Normal -->|"Site A fails<br/>(~5-10s)"| Failover
    Failover -->|"Site A restored<br/>(Zero downtime)"| Recovery
    Recovery -->|"Rebalance complete<br/>Re-apply lease_preferences"| Normal
```

## 8.4 Failover Timeline

```mermaid
sequenceDiagram
    participant App as Application
    participant LB_A as HAProxy<br/>Site A
    participant LB_B as HAProxy<br/>Site B
    participant N1 as Node 1<br/>Site A
    participant N2 as Node 2<br/>Site A
    participant N3 as Node 3<br/>Site B
    participant N4 as Node 4<br/>Site B
    participant N5 as Node 5<br/>Witness

    Note over App,N5: 🟢 Normal Operation - Site A is Primary
    App->>LB_A: SQL Query
    LB_A->>N1: Forward (Leader)
    N1->>N3: Replicate
    N1->>N5: Raft Vote
    N1-->>LB_A: Response
    LB_A-->>App: Result

    Note over App,N5: 🔴 DISASTER: Site A Network Failure
    App->>LB_A: SQL Query
    LB_A--xN1: Connection Lost
    LB_A--xN2: Connection Lost

    Note over N3,N5: ⏱️ T+0s: Raft detects failure
    N3->>N4: Leader Election
    N3->>N5: Request Vote
    N5-->>N3: Vote Granted
    N4-->>N3: Vote Granted

    Note over N3,N5: ⏱️ T+3-5s: New Leader Elected
    N3->>N3: Become Leader

    Note over App,N5: ⏱️ T+5-7s: HAProxy Health Check Fails
    LB_A-->>App: Connection Error
    App->>LB_B: Failover Connection

    Note over App,N5: ⏱️ T+7-10s: Service Restored via Site B
    LB_B->>N3: SQL Query (New Leader)
    N3->>N4: Replicate
    N3-->>LB_B: Response
    LB_B-->>App: Result

    Note over App,N5: 🟢 Total Downtime: ~5-10 seconds
```

## 8.5 Multi-Site HAProxy Configuration

```mermaid
flowchart TD
    subgraph SiteA_LB["Site A HAProxy Configuration"]
        direction TB
        A_Front["frontend postgresql<br/>bind *:26257"]
        A_Front --> A_Back["backend cockroachdb"]
        A_Back --> A_Primary["server n1 node1:26257 check<br/>server n2 node2:26257 check"]
        A_Back --> A_Backup["server n3 node3:26257 check backup<br/>server n4 node4:26257 check backup"]
    end

    subgraph SiteB_LB["Site B HAProxy Configuration"]
        direction TB
        B_Front["frontend postgresql<br/>bind *:26257"]
        B_Front --> B_Back["backend cockroachdb"]
        B_Back --> B_Primary["server n3 node3:26257 check<br/>server n4 node4:26257 check"]
        B_Back --> B_Backup["server n1 node1:26257 check backup<br/>server n2 node2:26257 check backup"]
    end

    App[Application]
    DNS["DNS / Load Balancer<br/>Primary: Site A<br/>Failover: Site B"]

    App --> DNS
    DNS -->|Primary| SiteA_LB
    DNS -.->|Failover| SiteB_LB
```

## 8.6 Witness Node Role

```mermaid
flowchart TB
    subgraph WitnessRole["Node 5: Witness Node Purpose"]
        direction TB
        W1["🗳️ Participates in Raft Voting"]
        W2["📊 Does NOT store data replicas"]
        W3["⚡ Lightweight: 1GB RAM, 1 CPU"]
        W4["🔒 Ensures quorum during Site A failure"]
    end

    subgraph QuorumMath["Quorum Mathematics"]
        direction TB
        Q1["Total Nodes: 5"]
        Q2["Quorum Required: 3 (majority)"]
        Q3["Site A Nodes: 2"]
        Q4["Site B Nodes: 3 (including Witness)"]
    end

    subgraph Scenarios["Failure Scenarios"]
        direction TB
        S1["✅ Site A Down (2 nodes)<br/>Remaining: 3 nodes = Quorum OK"]
        S2["✅ Any 2 nodes down<br/>Remaining: 3 nodes = Quorum OK"]
        S3["❌ 3+ nodes down<br/>Remaining: <3 = No Quorum"]
    end

    WitnessRole --> QuorumMath
    QuorumMath --> Scenarios
```

## 8.7 Data Replication Flow

```mermaid
flowchart LR
    subgraph Write["Write Operation"]
        direction TB
        W_App[Application] --> W_Leader["Node 1 (Leader)<br/>Site A"]
    end

    subgraph Replication["Raft Replication"]
        direction TB
        W_Leader --> R1["Replica 1<br/>Node 2 (Site A)"]
        W_Leader --> R2["Replica 2<br/>Node 3 (Site B)"]
        W_Leader -.-> R3["Node 5 (Witness)<br/>Vote Only, No Data"]
    end

    subgraph Acknowledge["Acknowledgment"]
        direction TB
        R1 --> ACK["Wait for 2/3 ACKs<br/>(Quorum)"]
        R2 --> ACK
        ACK --> Commit["Commit Transaction"]
    end

    Write --> Replication --> Acknowledge

    subgraph ZoneConfig["Zone Configuration"]
        Z1["num_replicas = 3"]
        Z2["Site A: 2 copies"]
        Z3["Site B: 1 copy"]
        Z4["Witness: 0 copies (vote only)"]
    end
```

## 8.8 Multi-Site Script Support Status

```mermaid
flowchart TD
    subgraph Supported["✅ Currently Supported"]
        S1["setup_os.sh<br/>Works for all nodes"]
        S2["setup_cockroach.sh<br/>Basic installation"]
        S3["setup_haproxy.sh<br/>Single site config"]
        S4["generate_certs.sh<br/>Multi-node certs"]
        S5["backup_cockroach.sh<br/>Generic backup"]
    end

    subgraph Manual["⚠️ Requires Manual Steps"]
        M1["Locality Flags<br/>Edit systemd manually"]
        M2["Zone Configuration<br/>Run SQL manually"]
        M3["Multi-Site HAProxy<br/>Configure backup servers"]
    end

    subgraph Missing["❌ Scripts Needed"]
        N1["setup_locality.sh<br/>Auto-inject locality"]
        N2["setup_zone_config.sh<br/>Configure replication"]
        N3["validate_multisite.sh<br/>Verify deployment"]
        N4["failover_test.sh<br/>Test DR scenarios"]
    end

    Supported --> Manual
    Manual --> Missing
```

## 9. Connection Flow Detail

```mermaid
sequenceDiagram
    participant App as Application
    participant PgB as PgBouncer<br/>:6432
    participant HAP as HAProxy<br/>:26257
    participant N1 as Node 1
    participant N2 as Node 2
    participant N3 as Node 3

    Note over App,N3: With PgBouncer (High Concurrency)
    App->>PgB: Connect (1 of 10000)
    PgB->>PgB: Pool: transaction mode
    PgB->>HAP: Reuse pooled connection
    HAP->>N1: Round-robin select
    N1-->>HAP: Response
    HAP-->>PgB: Forward
    PgB-->>App: Return result

    Note over App,N3: Without PgBouncer (Direct)
    App->>HAP: Connect directly
    HAP->>N2: Round-robin select
    N2-->>HAP: Response
    HAP-->>App: Return result

    Note over App,N3: Health Check
    loop Every 5 seconds
        HAP->>N1: TCP Check
        HAP->>N2: TCP Check
        HAP->>N3: TCP Check
        N1-->>HAP: OK
        N2-->>HAP: OK
        N3-->>HAP: OK
    end
```

## 10. Script Dependencies & Execution Order

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: OS Preparation"]
        setup_os[setup_os.sh]
        setup_lb_os[setup_loadbalancer_os.sh]
    end

    subgraph Phase2["Phase 2: Installation"]
        setup_crdb[setup_cockroach.sh]
        setup_ha[setup_haproxy.sh]
        setup_pgb[setup_pgbouncer.sh]
    end

    subgraph Phase3["Phase 3: Security"]
        gen_certs[generate_certs.sh]
    end

    subgraph Phase4["Phase 4: Operations"]
        backup[backup_cockroach.sh]
        restore[restore_cockroach.sh]
        auto_backup[setup_backup_automation.sh]
    end

    setup_os --> setup_crdb
    setup_lb_os --> setup_ha
    setup_ha --> setup_pgb
    setup_crdb --> gen_certs
    gen_certs --> backup
    backup --> auto_backup
    auto_backup --> restore

    setup_crdb -.->|Node IPs| setup_ha
    setup_ha -.->|HAProxy IP| setup_pgb
```

## 11. Decision Tree: When to Use Each Component

```mermaid
flowchart TD
    Start([Start Decision]) --> Q1{Expected Concurrent<br/>Connections?}

    Q1 -->|< 100| Simple["Simple Setup<br/>HAProxy Only"]
    Q1 -->|100-1000| Medium["Standard Setup<br/>HAProxy + Tuning"]
    Q1 -->|> 1000| High["Full Setup<br/>HAProxy + PgBouncer"]

    Simple --> Q2{Need HA/DR?}
    Medium --> Q2
    High --> Q2

    Q2 -->|No| Single["Single Site<br/>3 Nodes"]
    Q2 -->|Yes| Multi["Multi-Site<br/>2+3 Topology"]

    Single --> Q3{Security Mode?}
    Multi --> Q3

    Q3 -->|Development| Insecure["--insecure flag"]
    Q3 -->|Production| Secure["TLS Certificates<br/>generate_certs.sh"]

    Insecure --> Q4{Backup Strategy?}
    Secure --> Q4

    Q4 -->|Manual| ManualBackup["Run backup_cockroach.sh<br/>as needed"]
    Q4 -->|Automated| AutoBackup["setup_backup_automation.sh<br/>Cron scheduled"]

    ManualBackup --> End([Configuration Complete])
    AutoBackup --> End
```

## 12. Memory-Based Configuration Matrix

```mermaid
flowchart TD
    subgraph RAM["System RAM Detection"]
        R1["< 2GB"]
        R2["2-4GB"]
        R3["4-8GB"]
        R4["8-16GB"]
        R5["> 16GB"]
    end

    subgraph CockroachDB["CockroachDB Settings"]
        C1["cache=512MB<br/>sql-mem=512MB"]
        C2["cache=512MB-1GB<br/>sql-mem=512MB-1GB"]
        C3["cache=1-2GB<br/>sql-mem=1-2GB"]
        C4["cache=2-4GB<br/>sql-mem=2-4GB"]
        C5["cache=4GB+<br/>sql-mem=4GB+"]
    end

    subgraph HAProxy["HAProxy Settings"]
        H1["maxconn=1024<br/>timeout=30s"]
        H2["maxconn=2048<br/>timeout=1m"]
        H3["maxconn=4096<br/>timeout=2m"]
        H4["maxconn=8192<br/>timeout=5m"]
        H5["maxconn=50000<br/>timeout=5m"]
    end

    subgraph PgBouncer["PgBouncer Settings"]
        P1["⚠️ Not Recommended"]
        P2["max_client=2000"]
        P3["max_client=5000"]
        P4["max_client=10000"]
        P5["max_client=20000"]
    end

    R1 --> C1 --> H1 --> P1
    R2 --> C2 --> H2 --> P2
    R3 --> C3 --> H3 --> P3
    R4 --> C4 --> H4 --> P4
    R5 --> C5 --> H5 --> P5
```

---

## Quick Reference: Script Purposes

| Script | Purpose | Run On |
|--------|---------|--------|
| `setup_os.sh` | OS optimization for CockroachDB nodes | Each DB Node |
| `setup_loadbalancer_os.sh` | OS optimization for load balancer | LB Server |
| `setup_cockroach.sh` | Install CockroachDB binary & service | Each DB Node |
| `setup_haproxy.sh` | Install & configure HAProxy | LB Server |
| `setup_pgbouncer.sh` | Install & configure PgBouncer | LB Server |
| `generate_certs.sh` | Generate TLS certificates | Any Node |
| `backup_cockroach.sh` | Manual/automated backup | Any Node |
| `restore_cockroach.sh` | Restore from backup | Any Node |
| `setup_backup_automation.sh` | Configure cron for backups | Backup Node |
