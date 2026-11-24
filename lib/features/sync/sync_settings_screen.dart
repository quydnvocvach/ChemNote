import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import 'google_auth_service.dart';
import 'sync_manager.dart';

/// Màn hình cài đặt đồng bộ Google Drive (GMS-free cho Android & Huawei HarmonyOS).
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  String _configuredClientId = '';
  String _configuredClientSecret = '';
  bool _loadingClientId = true;

  @override
  void initState() {
    super.initState();
    _loadClientId();
  }

  Future<void> _loadClientId() async {
    final syncManager = context.read<SyncManager>();
    final id = await syncManager.authService.config.loadClientId();
    final secret = await syncManager.authService.config.loadClientSecret();
    if (!mounted) return;
    setState(() {
      _configuredClientId = id;
      _configuredClientSecret = secret;
      _loadingClientId = false;
    });
  }

  Future<void> _showClientIdDialog() async {
    final syncManager = context.read<SyncManager>();
    final idController = TextEditingController(text: _configuredClientId);
    final secretController =
        TextEditingController(text: _configuredClientSecret);
    var obscureSecret = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Cấu hình Google OAuth (Desktop app)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trên Google Cloud Console -> Create OAuth client ID -> chọn loại Desktop app (Ứng dụng dành cho máy tính), rồi dán cả Client ID và Client Secret vào đây (chạy chuẩn trên Huawei HarmonyOS không cần GMS & không lỗi 401).',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'Client ID',
                        hintText: '1234567890-xxxx.apps.googleusercontent.com',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: secretController,
                      obscureText: obscureSecret,
                      decoration: InputDecoration(
                        labelText: 'Client Secret (cho Desktop app)',
                        hintText: 'GOCSPX-xxxxxxxxxxxxxxxx',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: obscureSecret ? 'Hiện' : 'Ẩn',
                          icon: Icon(
                            obscureSecret
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscureSecret = !obscureSecret;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cơ chế xác thực RFC 8252 Loopback:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 4),
                          SelectableText(
                            'http://127.0.0.1:<port>/oauth2redirect',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_configuredClientId.isNotEmpty ||
                    _configuredClientSecret.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await syncManager.authService.config.clearClientId();
                      await syncManager.authService.config.clearClientSecret();
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
                    child: const Text('Xóa cấu hình'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () async {
                    await syncManager.authService.config
                        .saveClientId(idController.text);
                    await syncManager.authService.config
                        .saveClientSecret(secretController.text);
                    if (ctx.mounted) Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );

    idController.dispose();
    secretController.dispose();
    if (saved == true) {
      await _loadClientId();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật cấu hình Google OAuth.'),
        ),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final syncManager = context.read<SyncManager>();
    try {
      await syncManager.signInWithGoogle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng nhập Google Drive thành công!')),
      );
    } on GoogleAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      if (e.needsClientId) {
        await _showClientIdDialog();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể đăng nhập: $e')),
      );
    }
  }

  Future<void> _handleDemoSignIn() async {
    final syncManager = context.read<SyncManager>();
    await syncManager.signInDemoMode();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã kích hoạt Chế độ Demo Google Drive.'),
      ),
    );
  }

  Future<void> _handleSyncNow() async {
    final syncManager = context.read<SyncManager>();
    await syncManager.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(syncManager.statusMessage)),
    );
  }

  Future<void> _handleRestore() async {
    final syncManager = context.read<SyncManager>();
    final count = await syncManager.restoreFromDrive();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Đã khôi phục $count sổ tay từ Google Drive.'
              : syncManager.statusMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncManager = context.watch<SyncManager>();
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFmt = DateFormat('HH:mm:ss • dd/MM/yyyy');
    final logTimeFmt = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng bộ Google Drive'),
        actions: [
          IconButton(
            tooltip: 'Cấu hình OAuth Client ID',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _showClientIdDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Thẻ tài khoản & huy hiệu tương thích HarmonyOS không cần GMS
          _buildAccountCard(
            context,
            syncManager: syncManager,
            dateFmt: dateFmt,
          ),
          const SizedBox(height: 16),

          // 2. Điều khiển đồng bộ & Tự động đồng bộ
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.sync_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('Tự động đồng bộ khi có mạng'),
                  subtitle: const Text(
                    'Tự động tải lên các thay đổi sau khi chỉnh sửa sổ tay (ưu tiên ngoại tuyến).',
                  ),
                  value: syncManager.autoSyncEnabled,
                  onChanged: syncManager.setAutoSyncEnabled,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            syncManager.isOnline
                                ? Icons.wifi_rounded
                                : Icons.wifi_off_rounded,
                            size: 18,
                            color: syncManager.isOnline
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              syncManager.statusMessage,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      if (syncManager.lastSyncedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Lần đồng bộ gần nhất: ${dateFmt.format(syncManager.lastSyncedAt!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (!syncManager.isSignedIn ||
                                      syncManager.isSyncing)
                                  ? null
                                  : _handleSyncNow,
                              icon: syncManager.isSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Đồng bộ ngay'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (!syncManager.isSignedIn ||
                                      syncManager.isSyncing)
                                  ? null
                                  : _handleRestore,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Khôi phục Drive'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Danh sách trạng thái đồng bộ từng sổ tay
          Text(
            'Trạng thái sổ tay (${appState.notebooks.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (appState.notebooks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chưa có sổ tay nào trong thư viện.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < appState.notebooks.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _buildNotebookStatusTile(
                      context,
                      appState.notebooks[i],
                      dateFmt,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),

          // 4. Nhật ký hoạt động đồng bộ
          Text(
            'Nhật ký đồng bộ',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: syncManager.syncLogs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Chưa có hoạt động đồng bộ nào.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: syncManager.syncLogs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final entry = syncManager.syncLogs[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          entry.isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: entry.isError
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        title: Text(
                          entry.message,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          logTimeFmt.format(entry.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context, {
    required SyncManager syncManager,
    required DateFormat dateFmt,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = syncManager.currentUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Huy hiệu tương thích HarmonyOS không cần Google Play Services
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: Icon(
                    Icons.verified_user_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  label: const Text(
                    'Android & HarmonyOS • Không cần GMS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (syncManager.isDemoMode)
                  Chip(
                    avatar: const Icon(Icons.science_outlined, size: 16),
                    label: const Text(
                      'Chế độ Demo',
                      style: TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (user != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : 'G',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          user.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        syncManager.isSyncing ? null : syncManager.signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Đăng xuất'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Sao lưu & đồng bộ sổ tay Hóa học',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sử dụng OAuth 2.0 + PKCE qua trình duyệt hệ thống và Google Drive REST API v3, hoạt động ổn định trên điện thoại/máy tính bảng Huawei HarmonyOS không có Google Play Services.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (!_loadingClientId)
                Text(
                  _configuredClientId.isEmpty
                      ? 'Trạng thái OAuth: Chưa cấu hình (có thể dùng Chế độ Demo ngay)'
                      : 'Client ID: ${_maskClientId(_configuredClientId)}'
                          '${_configuredClientSecret.isNotEmpty ? ' • Đã có Client Secret' : ' • Chưa nhập Client Secret'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _configuredClientId.isEmpty
                        ? colorScheme.tertiary
                        : Colors.green,
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _handleGoogleSignIn,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Đăng nhập Google Drive'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showClientIdDialog,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Cấu hình OAuth'),
                  ),
                  TextButton.icon(
                    onPressed: _handleDemoSignIn,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Dùng Chế độ Demo'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotebookStatusTile(
    BuildContext context,
    Notebook notebook,
    DateFormat dateFmt,
  ) {
    final (label, color, icon) = switch (notebook.syncStatus) {
      SyncStatus.synced => (
          'Đã đồng bộ',
          Colors.green,
          Icons.cloud_done_outlined,
        ),
      SyncStatus.pendingUpload => (
          'Chờ tải lên',
          Colors.orange,
          Icons.cloud_upload_outlined,
        ),
      SyncStatus.syncing => (
          'Đang đồng bộ',
          Colors.blue,
          Icons.sync_rounded,
        ),
      SyncStatus.error => (
          'Lỗi đồng bộ',
          Colors.red,
          Icons.cloud_off_rounded,
        ),
      SyncStatus.localOnly => (
          'Chỉ trên máy',
          Colors.grey,
          Icons.smartphone_outlined,
        ),
    };

    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Color(notebook.coverColorValue),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          notebook.isLocked
              ? Icons.lock_outline_rounded
              : notebook.isTrashed
                  ? Icons.delete_outline_rounded
                  : Icons.menu_book_outlined,
          color: Colors.white,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              notebook.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (notebook.isFavorite)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.star_rounded,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (notebook.isLocked)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${notebook.pages.length} trang'
        '${notebook.isTrashed ? ' • Thùng rác' : ''}'
        ' • Cập nhật ${dateFmt.format(notebook.updatedAt)}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(31),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _maskClientId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}
