import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color(0xFFFF0000),
      ),
      home: const RemoteControlScreen(),
    );
  }
}

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.1");
  final TextEditingController _portController = TextEditingController(text: "55555");
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Socket? _socket;
  bool _isLoading = false;
  bool _isConnected = false;
  bool _showLogs = true;
  List<Map<String, dynamic>> logs = [];

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  final String _batScriptContent = r'''@echo off
title serveur local
echo lancement du serveur sur le port 55555...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$listener = [System.Net.Sockets.TcpListener]55555; $listener.Start(); while ($true) { $client = $listener.AcceptTcpClient(); $stream = $client.GetStream(); $reader = New-Object System.IO.StreamReader($stream); $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true; $writer.WriteLine('connecté au pc windows'); while ($client.Connected) { $cmd = $reader.ReadLine(); if ($cmd -eq $null) { break }; try { $out = Invoke-Expression $cmd 2>&1 | Out-String; if ([string]::IsNullOrWhiteSpace($out)) { $out = 'commande exécutée sans retour.' }; $writer.WriteLine($out); } catch { $writer.WriteLine('erreur: ' + $_.Exception.Message); } } $client.Close(); }"
pause''';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _commandController.dispose();
    _scrollController.dispose();
    _socket?.destroy();
    super.dispose();
  }

  void _addLog(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      logs.add({
        "text": "[${DateTime.now().toString().substring(11, 19)}] ${message.toLowerCase()}",
        "isError": isError
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToBatScript() async {
    final logMessage = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => BatScriptScreen(scriptContent: _batScriptContent),
      ),
    );
    
    if (logMessage != null) {
      _addLog(logMessage);
    }
  }

  void _navigateToHelp() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConnectionHelpScreen(),
      ),
    );
  }

  void _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      _addLog("erreur : ip ou port invalide", isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _addLog("connexion à $ip:$port...");

    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
      
      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
      _addLog("connexion établie");

      _socket!.listen(
        (List<int> data) {
          final response = utf8.decode(data).trim();
          _addLog(response);
        },
        onError: (error) {
          _addLog("erreur réseau : $error", isError: true);
          _disconnect();
        },
        onDone: () {
          _addLog("connexion interrompue par la cible");
          _disconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
      _addLog("échec : cible introuvable ($e)", isError: true);
    }
  }

  void _disconnect() {
    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
    setState(() {
      _isConnected = false;
      _isLoading = false;
    });
    _addLog("déconnecté");
  }

  void _handleCommandExecution() {
    final input = _commandController.text.trim();
    if (input.isEmpty) return;

    _commandController.clear();

    if (_socket == null) {
      _addLog("erreur : aucun appareil connecté", isError: true);
      return;
    }
    try {
      _socket!.write("$input\n");
      _addLog("> $input");
    } catch (e) {
      _addLog("erreur d'envoi : $e", isError: true);
    }
  }

  // Fonction mise à jour prenant la taille optionnelle en second paramètre
  InputDecoration _customInputStyle(String label, [double fontSize = 13]) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white24, fontSize: fontSize),
      filled: true,
      fillColor: const Color(0xFF0A0A0A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFFF0000), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BX Remote", style: TextStyle(fontSize: 18, letterSpacing: 1)),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _navigateToBatScript,
            child: const Text("copier le .bat", style: TextStyle(color: Color(0xFFFF0000), fontSize: 13)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    decoration: _customInputStyle("Adresse IP cible", 16),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    decoration: _customInputStyle("Port", 16),
                  ),
                ),
              ],
            ),
            
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _navigateToHelp,
                icon: const Icon(Icons.help_outline, color: Color(0xFFFF0000), size: 15),
                label: const Text(
                  "comment se connecter ?",
                  style: TextStyle(color: Color(0xFFFF0000), fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 25),

            GestureDetector(
              onTapDown: (_) => _animationController.forward(),
              onTapUp: (_) {
                _animationController.reverse();
                if (!_isLoading) _toggleConnection();
              },
              onTapCancel: () => _animationController.reverse(),
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
                              strokeWidth: 2,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isConnected ? const Color(0xFFFF0000) : Colors.white10,
                                  width: 1.5,
                                ),
                              ),
                            ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFF000000) : const Color(0xFFFF0000),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF0000),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _isConnected ? Icons.close : Icons.sensors,
                          color: _isConnected ? const Color(0xFFFF0000) : Colors.black,
                          size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isConnected ? "status : connecté" : "statut : deconnecté",
              style: TextStyle(
                fontSize: 15,
                color: _isConnected ? const Color(0xFFFF0000) : Colors.white24,
              ),
            ),
            const SizedBox(height: 35),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: _customInputStyle("commandes a distance"),
                    onSubmitted: (_) => _handleCommandExecution(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF0000),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: _handleCommandExecution,
                    child: const Icon(Icons.arrow_forward, size: 19),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                const Text("logs", style: TextStyle(color: Colors.white24, fontSize: 13)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showLogs = !_showLogs),
                  child: Text(
                    _showLogs ? "< masquer" : "> afficher",
                    style: const TextStyle(color: Color(0xFFFF0000), fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_showLogs)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF050505),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logItem = logs[index];
                      final bool isError = logItem["isError"] ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          logItem["text"] ?? "",
                          style: TextStyle(
                            color: isError ? const Color(0xFFFF3333) : Colors.white70,
                            fontFamily: "monospace",
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BatScriptScreen extends StatefulWidget {
  final String scriptContent;
  const BatScriptScreen({super.key, required this.scriptContent});

  @override
  State<BatScriptScreen> createState() => _BatScriptScreenState();
}

class _BatScriptScreenState extends State<BatScriptScreen> {
  late TextEditingController _scriptController;

  @override
  void initState() {
    super.initState();
    _scriptController = TextEditingController(text: widget.scriptContent);
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text("configuration server .bat", style: TextStyle(fontSize: 14, fontFamily: "monospace")),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFFF0000)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _scriptController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(color: Colors.white70, fontFamily: "monospace", fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF050505),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFFFF0000)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0000),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _scriptController.text));
                  Navigator.pop(context, "script .bat personnalisé copié.");
                },
                child: const Text("copier le script", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionHelpScreen extends StatelessWidget {
  const ConnectionHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        appBar: AppBar(
          title: const Text("guide de connexion", style: TextStyle(fontSize: 15, fontFamily: "monospace")),
          backgroundColor: const Color(0xFF000000),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFFF0000)),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF0000),
            labelColor: Color(0xFFFF0000),
            unselectedLabelColor: Colors.white30,
            indicatorWeight: 2,
            tabs: [
              Tab(text: "windows"),
              Tab(text: "macos"),
              Tab(text: "android"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            WindowsHelpView(),
            MacHelpView(),
            AndroidHelpView(),
          ],
        ),
      ),
    );
  }
}

class HelpStepToggle extends StatelessWidget {
  final String title;
  final String content;

  const HelpStepToggle({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: const Color(0xFFFF0000),
          collapsedIconColor: Colors.white38,
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  content,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4, fontFamily: "monospace"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WindowsHelpView extends StatelessWidget {
  const WindowsHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        HelpStepToggle(
          title: "etape 1 : creer un dossier securise",
          content: "Pour éviter que Windows Defender ou votre pare-feu bloque l'application, évitez le dossier /Downloads.\n\nCréez un dossier neuf à la racine de votre système, par exemple : C:\\BXRemote.",
        ),
        HelpStepToggle(
          title: "etape 2 : autorisations du dossier",
          content: "Faites un clic droit sur votre dossier créé -> Propriétés -> Sécurité.\n\nVérifiez que votre session utilisateur possède le contrôle total sur ce dossier afin d'exécuter des fichiers sans contraintes.",
        ),
        HelpStepToggle(
          title: "etape 3 : deploiement du script .bat",
          content: "1. Copiez le script .bat depuis l'application.\n2. Dans votre dossier sécurisé, créez un document texte nommé 'serveur.bat'.\n3. Collez le code dedans et sauvegardez.\n4. Double-cliquez pour exécuter l'écouteur sur le port 55555.",
        ),
        HelpStepToggle(
          title: "etape 4 : recuperer l adresse ip locale",
          content: "Ouvrez l'invite de commande (cmd) sur votre PC, tapez 'ipconfig' et repérez la ligne 'Adresse IPv4' (ex: 192.168.1.35).\n\nEntrez cette IP et le port 55555 dans l'application pour initier la liaison.",
        ),
      ],
    );
  }
}

class MacHelpView extends StatelessWidget {
  const MacHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        HelpStepToggle(
          title: "etape 1 : configurer un repertoire isole",
          content: "macOS restreint l'activité réseau brute dans le dossier Téléchargements standard.\n\nOuvrez votre Finder et créez un dossier isolé dans votre dossier utilisateur (ex: /Utilisateurs/votre-nom/BXConsole).",
        ),
        HelpStepToggle(
          title: "etape 2 : demarrer l ecoute reseau",
          content: "Ouvrez l'application Terminal sur votre Mac et déplacez-vous dans votre dossier sécurisé.\n\nTapez la commande de socket suivante pour ouvrir le port d'écoute :\nnc -l 55555",
        ),
        HelpStepToggle(
          title: "etape 3 : autoriser les flux entrants",
          content: "Si le système d'exploitation macOS affiche une alerte de sécurité, acceptez explicitement la demande d'autorisation réseau pour le Terminal.",
        ),
        HelpStepToggle(
          title: "etape 4 : renseigner l ip locale",
          content: "Allez dans Réglages Système -> Réseau -> Wi-Fi ou Ethernet -> Détails.\n\nNotez l'adresse IP locale affichée, renseignez-la dans BX Remote, puis validez.",
        ),
      ],
    );
  }
}

class AndroidHelpView extends StatelessWidget {
  const AndroidHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        HelpStepToggle(
          title: "etape 1 : installer un emulateur terminal",
          content: "Pour que votre appareil Android puisse recevoir des commandes en local, téléchargez un émulateur de console réseau (ex: Termux) depuis une bibliothèque sécurisée.",
        ),
        HelpStepToggle(
          title: "etape 2 : initialiser l ecoute locale",
          content: "Ouvrez votre application de terminal Android (Termux) puis saisissez l'instruction suivante pour ouvrir le canal réseau interne :\nnc -l -p 55555",
        ),
        HelpStepToggle(
          title: "etape 3 : verifier l ip reseau de l appareil",
          content: "Allez dans Paramètres Android -> À propos du téléphone -> Statut (ou Infos d'état) -> Adresse IP.\n\nTant que l'appareil reste connecté au même réseau Wi-Fi local que cet appareil Android, la liaison s'effectuera directement via cette IP.",
        ),
      ],
    );
  }
}
