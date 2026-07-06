import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/data_service.dart';

class AdminContactsScreen extends StatefulWidget {
  const AdminContactsScreen({super.key});
  @override
  State<AdminContactsScreen> createState() => _AdminContactsScreenState();
}

class _AdminContactsScreenState extends State<AdminContactsScreen> {
  final _ds = DataService();
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final contacts = _ds.adminContacts;
    setState(() { _contacts = List.from(contacts); _isLoading = false; });
  }

  Future<void> _save() async {
    await _ds.saveAdminContacts(_contacts);
    _snackOk('✅ Contacts sauvegardés');
  }

  void _snackOk(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visible   = _contacts.where((c) => c['hidden'] != true).toList();
    final hidden    = _contacts.where((c) => c['hidden'] == true).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Gestion des Contacts',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
            label: const Text('Sauvegarder',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showContactDialog(),
        backgroundColor: AppTheme.accentColor,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Nouveau contact',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Info banner ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: AppTheme.accentColor, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Ces contacts apparaissent sur la page publique pour permettre aux visiteurs de vous joindre.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppTheme.accentColor, height: 1.4),
                    )),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Contacts visibles ────────────────────────────────────────
                _sectionHeader('Contacts visibles (${visible.length})'),
                const SizedBox(height: 10),
                if (visible.isEmpty)
                  _emptyCard('Aucun contact visible')
                else
                  ...visible.map((c) => _contactCard(c, _contacts.indexOf(c))),
                const SizedBox(height: 20),

                // ── Contacts masqués ─────────────────────────────────────────
                if (hidden.isNotEmpty) ...[
                  _sectionHeader('Contacts masqués (${hidden.length})'),
                  const SizedBox(height: 10),
                  ...hidden.map((c) => _contactCard(c, _contacts.indexOf(c))),
                ],
              ]),
            ),
    );
  }

  Widget _sectionHeader(String title) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryDark]),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(title, style: const TextStyle(fontFamily: 'Poppins',
        fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
  );

  Widget _emptyCard(String msg) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor)),
    child: Center(child: Text(msg, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textHint))),
  );

  Widget _contactCard(Map<String, dynamic> c, int index) {
    final isHidden = c['hidden'] == true;
    final typeIcons = <String, IconData>{
      'whatsapp': Icons.chat_rounded,
      'phone': Icons.phone_rounded,
      'email': Icons.email_rounded,
      'facebook': Icons.facebook_rounded,
      'website': Icons.language_rounded,
      'other': Icons.contact_page_rounded,
    };
    final typeColors = <String, Color>{
      'whatsapp': const Color(0xFF25D366),
      'phone': AppTheme.accentColor,
      'email': const Color(0xFF4285F4),
      'facebook': const Color(0xFF1877F2),
      'website': AppTheme.primaryLight,
      'other': AppTheme.textSecondary,
    };
    final type = c['type'] ?? 'other';
    final color = typeColors[type] ?? AppTheme.textSecondary;
    final icon  = typeIcons[type]  ?? Icons.contact_page_rounded;

    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: () => _showContactDialog(index: index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isHidden ? Colors.grey[50] : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isHidden ? AppTheme.dividerColor : color.withValues(alpha: 0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isHidden ? 0.05 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isHidden ? Colors.grey : color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['label'] ?? '', style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
              color: isHidden ? AppTheme.textHint : AppTheme.textPrimary,
            )),
            const SizedBox(height: 2),
            MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: c['value'] ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Copié : ${c['value']}', style: const TextStyle(fontFamily: 'Poppins')),
                  backgroundColor: AppTheme.successColor, duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              child: Row(children: [
                Expanded(child: Text(c['value'] ?? '', style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: isHidden ? AppTheme.textHint : color,
                  fontWeight: FontWeight.w600,
                ))),
                Icon(Icons.copy_rounded, size: 12, color: isHidden ? AppTheme.textHint : color),
              ]),
            )),
          ])),
          if (isHidden)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              child: const Text('Masqué', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppTheme.textHint)),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'toggle',
                  child: Row(children: [
                    Icon(isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        size: 16, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Text(isHidden ? 'Afficher' : 'Masquer',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  ])),
              const PopupMenuItem(value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentColor),
                    SizedBox(width: 8),
                    Text('Modifier', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  ])),
              const PopupMenuItem(value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: AppTheme.errorColor),
                    SizedBox(width: 8),
                    Text('Supprimer', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.errorColor)),
                  ])),
            ],
            onSelected: (val) {
              if (val == 'toggle') setState(() { _contacts[index]['hidden'] = !isHidden; });
              if (val == 'edit')   _showContactDialog(index: index);
              if (val == 'delete') _confirmDelete(index, c['label'] ?? 'ce contact');
)            },
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(int index, String label) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer le contact', style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary)),
        content: Text('Supprimer "$label" définitivement ?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); setState(() => _contacts.removeAt(index)); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showContactDialog({int? index}) {
    final isEdit = index != null;
    final contact = isEdit ? Map<String, dynamic>.from(_contacts[index]) : <String, dynamic>{
      'id': 'ct_${DateTime.now().millisecondsSinceEpoch}',
      'label': '', 'value': '', 'type': 'phone', 'hidden': false,
    };
    final labelCtrl = TextEditingController(text: contact['label'] ?? '');
    final valueCtrl = TextEditingController(text: contact['value'] ?? '');
    String type = contact['type'] ?? 'phone';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Modifier le contact' : 'Nouveau contact',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 16, color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgField(labelCtrl, 'Libellé (ex: WhatsApp ImmoZone)', Icons.label_outline),
            const SizedBox(height: 12),
            _dlgField(valueCtrl, 'Valeur (numéro, email, URL...)', Icons.contact_page_outlined),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: _dlgDeco('Type de contact', Icons.category_outlined),
              onChanged: (v) => setS(() => type = v!),
              items: const [
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp', style: TextStyle(fontFamily: 'Poppins'))),
                DropdownMenuItem(value: 'phone',    child: Text('Téléphone', style: TextStyle(fontFamily: 'Poppins'))),
                DropdownMenuItem(value: 'email',    child: Text('Email', style: TextStyle(fontFamily: 'Poppins'))),
                DropdownMenuItem(value: 'facebook', child: Text('Facebook', style: TextStyle(fontFamily: 'Poppins'))),
                DropdownMenuItem(value: 'website',  child: Text('Site web', style: TextStyle(fontFamily: 'Poppins'))),
                DropdownMenuItem(value: 'other',    child: Text('Autre', style: TextStyle(fontFamily: 'Poppins'))),
              ],
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (labelCtrl.text.trim().isEmpty || valueCtrl.text.trim().isEmpty) return;
              final updated = {...contact, 'label': labelCtrl.text.trim(), 'value': valueCtrl.text.trim(), 'type': type};
              setState(() {
                if (isEdit) {
                  _contacts[index] = updated;
                } else {
                  _contacts.add(updated);
                }
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(isEdit ? 'Modifier' : 'Ajouter',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      )),
    );
  }

  Widget _dlgField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl, keyboardType: type,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: _dlgDeco(hint, icon),
    );
  }

  InputDecoration _dlgDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12),
    prefixIcon: Icon(icon, color: AppTheme.accentColor, size: 18),
    filled: true, fillColor: AppTheme.backgroundColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accentColor, width: 2)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.dividerColor)),
  );
}
