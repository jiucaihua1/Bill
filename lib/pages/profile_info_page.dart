import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app/auto_save.dart';
import '../app/avatar_picker.dart';
import '../app/common_widgets.dart';
import '../app/image_cropper.dart';
import '../l10n/app_localizations.dart';
import '../app/models.dart';
import '../app/veri_fin_scope.dart';
import 'profile_widgets.dart';

class ProfileInfoPage extends StatefulWidget {
  const ProfileInfoPage({super.key});

  @override
  State<ProfileInfoPage> createState() => _ProfileInfoPageState();
}

class _ProfileInfoPageState extends State<ProfileInfoPage> {
  late final AutoSave _autoSave;
  late TextEditingController _nicknameController;
  late TextEditingController _bioController;
  late TextEditingController _cityController;
  late TextEditingController _occupationController;
  late VoidCallback _detachNickname;
  late VoidCallback _detachBio;
  late VoidCallback _detachCity;
  late VoidCallback _detachOccupation;
  late String _avatarDataUrl;
  ProfileGender _gender = ProfileGender.unset;
  String _birthday = '';
  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final controller = VeriFinScope.of(context);
    _autoSave = AutoSave(save: _save, logger: controller.logger);
    final profile = controller.profile;
    _nicknameController = TextEditingController(text: profile.nickname);
    _bioController = TextEditingController(text: profile.bio);
    _cityController = TextEditingController(text: profile.city);
    _occupationController = TextEditingController(text: profile.occupation);
    _avatarDataUrl = profile.avatarDataUrl;
    _gender = profile.gender;
    _birthday = profile.birthday;
    _detachNickname = bindAutoSaveText(_nicknameController, _handleTextChanged);
    _detachBio = bindAutoSaveText(_bioController, _handleTextChanged);
    _detachCity = bindAutoSaveText(_cityController, _handleTextChanged);
    _detachOccupation = bindAutoSaveText(
      _occupationController,
      _handleTextChanged,
    );
  }

  @override
  void dispose() {
    _detachNickname();
    _detachBio();
    _detachCity();
    _detachOccupation();
    _autoSave.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _autoSave.schedule();
  }

  void _apply(VoidCallback update) {
    setState(update);
    _autoSave.schedule(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tokens = VeriStyleTokens.of(context);

    return AutoSavePopScope(
      autoSave: _autoSave,
      child: Scaffold(
        body: SafeArea(
          child: VeriPage(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: <Widget>[
                VeriHeader(title: l10n.personalInfo, showBack: true),
                const SizedBox(height: 10),
                AutoSaveFailureBanner(autoSave: _autoSave),
                Center(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                      onTap: _pickAvatar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 7,
                          children: [
                            Ink(
                              padding: const EdgeInsets.all(4),
                              decoration: ShapeDecoration(
                                color: tokens.raisedSurfaceColor,
                                shape: CircleBorder(
                                  side: BorderSide(
                                    color: Color.lerp(
                                      tokens.borderColor,
                                      theme.colorScheme.primary,
                                      0.24,
                                    )!,
                                  ),
                                ),
                              ),
                              child: ProfileAvatar(
                                profile: controller.profile.copyWith(
                                  avatarDataUrl: _avatarDataUrl,
                                ),
                                radius: 36,
                              ),
                            ),
                            Text(
                              l10n.changeAvatarLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                VeriCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      _textField(
                        context,
                        l10n.nicknameLabel,
                        _nicknameController,
                      ),
                      _textField(
                        context,
                        l10n.bioLabel,
                        _bioController,
                        lines: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                VeriCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnchoredMenuChoice<ProfileGender>(
                        key: const Key('profile_gender_choice'),
                        values: ProfileGender.values,
                        selected: _gender,
                        idOf: (value) => 'profile_gender_${value.name}',
                        labelOf: (value) => value.label(l10n),
                        iconOf: (value) => switch (value) {
                          ProfileGender.unset => Icons.remove_circle_outline,
                          ProfileGender.male => Icons.male_rounded,
                          ProfileGender.female => Icons.female_rounded,
                        },
                        onSelected: (value) => _apply(() => _gender = value),
                        semanticLabel: l10n.pickGenderTitle,
                        builder: (context, openMenu, menuOpen) => SettingsRow(
                          title: l10n.genderLabel,
                          trailing: _gender.label(l10n),
                          icon: Icons.person_outline,
                          trailingIcon: menuOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          onTap: openMenu,
                        ),
                      ),
                      Divider(height: 1, color: tokens.borderColor),
                      Row(
                        key: const Key('profile_birthday_field'),
                        children: [
                          Expanded(
                            child: SettingsRow(
                              title: l10n.birthdayLabel,
                              trailing: _birthday.isEmpty
                                  ? l10n.clearOption
                                  : _birthday,
                              icon: Icons.cake_outlined,
                              trailingIcon: Icons.chevron_right,
                              onTap: _pickBirthday,
                            ),
                          ),
                          if (_birthday.isNotEmpty)
                            IconButton(
                              key: const Key('profile_birthday_clear'),
                              tooltip: l10n.birthdayClear,
                              onPressed: _clearBirthday,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _textField(context, l10n.cityLabel, _cityController),
                      const SizedBox(height: 12),
                      _textField(
                        context,
                        l10n.occupationLabel,
                        _occupationController,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    int lines = 1,
  }) {
    final theme = Theme.of(context);
    final tokens = VeriStyleTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            maxLines: lines,
            decoration: InputDecoration(
              filled: true,
              fillColor: Color.lerp(
                tokens.cardColor,
                tokens.surfaceAltColor,
                0.56,
              ),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBirthday() async {
    final initial = DateTime.tryParse(_birthday) ?? DateTime(1998);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      _apply(() {
        _birthday =
            '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _clearBirthday() {
    _apply(() => _birthday = '');
  }

  Future<void> _pickAvatar() async {
    final rawImage = await pickRawImageDataUrl();
    if (rawImage == null || !mounted) {
      return;
    }
    final crop = await showImageCropper(
      context: context,
      imageDataUrl: rawImage,
      title: AppLocalizations.of(context).cropAvatarTitle,
      aspectRatio: 1,
      circlePreview: true,
    );
    if (crop == null || !mounted) {
      return;
    }
    final avatar = await runWithLoadingDialog<String?>(
      context: context,
      message: AppLocalizations.of(context).avatarGenerating,
      task: () => cropImageDataUrl(
        sourceDataUrl: rawImage,
        targetWidth: 512,
        targetHeight: 512,
        zoom: crop.zoom,
        offsetX: crop.offsetX,
        offsetY: crop.offsetY,
      ),
    );
    if (avatar != null && mounted) {
      _apply(() => _avatarDataUrl = avatar);
    }
  }

  UserProfile _draftProfile({required bool useNicknameFallback}) {
    final nickname = _nicknameController.text.trim();
    return UserProfile(
      nickname: useNicknameFallback && nickname.isEmpty
          ? defaultProfileNickname
          : nickname,
      bio: _bioController.text.trim(),
      avatarDataUrl: _avatarDataUrl,
      gender: _gender,
      birthday: _birthday,
      city: _cityController.text.trim(),
      occupation: _occupationController.text.trim(),
    );
  }

  Future<bool> _save() => VeriFinScope.of(
    context,
  ).saveProfileDraft(_draftProfile(useNicknameFallback: true));
}
