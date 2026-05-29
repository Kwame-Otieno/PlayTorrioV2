import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/stream_source.dart';
import 'local_server_service.dart';
import '../webstreamr/extractor/doodstream.dart';
import '../webstreamr/extractor/dropload.dart';
import '../webstreamr/extractor/external_url.dart';
import '../webstreamr/extractor/extractor.dart';
import '../webstreamr/extractor/extractor_registry.dart';
import '../webstreamr/extractor/fastream.dart';
import '../webstreamr/extractor/filelions.dart';
import '../webstreamr/extractor/filemoon.dart';
import '../webstreamr/extractor/fsst.dart';
import '../webstreamr/extractor/hubcloud.dart';
import '../webstreamr/extractor/hubdrive.dart';
import '../webstreamr/extractor/kinoger.dart' as ext_kinoger;
import '../webstreamr/extractor/lulustream.dart';
import '../webstreamr/extractor/mixdrop.dart';
import '../webstreamr/extractor/rgshows.dart' as ext_rgshows;
import '../webstreamr/extractor/savefiles.dart';
import '../webstreamr/extractor/streamembed.dart';
import '../webstreamr/extractor/streamtape.dart';
import '../webstreamr/extractor/supervideo.dart';
import '../webstreamr/extractor/uqload.dart';
import '../webstreamr/extractor/vidora.dart';
import '../webstreamr/extractor/vidsrc.dart' as ext_vidsrc;
import '../webstreamr/extractor/vixsrc.dart' as ext_vixsrc;
import '../webstreamr/extractor/voe.dart';
import '../webstreamr/extractor/youtube.dart';
import '../webstreamr/source/cinehdplus.dart';
import '../webstreamr/source/cuevana.dart';
import '../webstreamr/source/einschalten.dart';
import '../webstreamr/source/eurostreaming.dart';
import '../webstreamr/source/fourkhdhub.dart';
import '../webstreamr/source/frembed.dart';
import '../webstreamr/source/frenchcloud.dart';
import '../webstreamr/source/hdhub4u.dart';
import '../webstreamr/source/vegamovies.dart';
import '../webstreamr/source/homecine.dart';
import '../webstreamr/source/kinoger.dart';
import '../webstreamr/source/kokoshka.dart';
import '../webstreamr/source/megakino.dart';
import '../webstreamr/source/meinecloud.dart';
import '../webstreamr/source/mostraguarda.dart';
import '../webstreamr/source/movix.dart';
import '../webstreamr/source/rgshows.dart';
import '../webstreamr/source/source.dart';
import '../webstreamr/source/streamkiste.dart';
import '../webstreamr/source/verhdlink.dart';
import '../webstreamr/source/vidsrc.dart';
import '../webstreamr/source/vixsrc.dart';
import '../webstreamr/stream_resolver.dart';
import '../webstreamr/types.dart';
import '../webstreamr/utils/config.dart';
import '../webstreamr/utils/env.dart';
import '../webstreamr/utils/fetcher.dart';
import '../webstreamr/utils/id.dart';
import 'webstreamr_settings.dart';

/// Native, on-device port of webstreamr — does NOT hit any remote addon.
/// Builds Stremio-shaped streams locally via the 20-source / 25-extractor
/// pipeline and flattens them to [StreamSource] for the existing player UI.
class WebStreamrService {
  static final WebStreamrService _instance = WebStreamrService._internal();
  factory WebStreamrService() => _instance;
  WebStreamrService._internal();

  static bool _initialized = false;
  static late Fetcher _fetcher;
  static late ExtractorRegistry _registry;
  static late List<Source> _sources;
  static late StreamResolver _resolver;

  // Blacklisted sources (temporarily disabled due to failures)
  static const _blacklistedSources = {
    'vixsrc',  // Extractor broken: token/expires/url not found
    'rgshows', // DNS failure: api.rgshows.ru unreachable
  };

  /// Call once at app start (safe to call repeatedly — re-applies env).
  static Future<void> init() async {
    final tmdbToken = await WebStreamrSettings.getTmdbAccessToken();
    WsEnv.load({
      'MANIFEST_ID': 'webstreamr',
      'MANIFEST_NAME': 'WebStreamr',
      'NODE_ENV': kReleaseMode ? 'production' : 'development',
      if (tmdbToken != null && tmdbToken.isNotEmpty)
        'TMDB_ACCESS_TOKEN': tmdbToken,
    });

    if (_initialized) return;
    _initialized = true;

    // Initialize fetcher
    _fetcher = Fetcher(
      logger: (msg) => debugPrint('[WS] $msg'),
    );

    final hubCloud = HubCloud(_fetcher);

    final extractors = <Extractor>[
      DoodStream(_fetcher),
      Dropload(_fetcher),
      Fastream(_fetcher),
      FileLions(_fetcher),
      FileMoon(_fetcher),
      Fsst(_fetcher),
      hubCloud,
      HubDrive(_fetcher, hubCloud),
      ext_kinoger.KinoGer(_fetcher),
      LuluStream(_fetcher),
      Mixdrop(_fetcher),
      ext_rgshows.RgShows(_fetcher),
      SaveFiles(_fetcher),
      StreamEmbed(_fetcher),
      Streamtape(_fetcher),
      SuperVideo(_fetcher),
      Uqload(_fetcher),
      Vidora(_fetcher),
      ext_vidsrc.VidSrc(_fetcher, const [
        'vidsrcme.ru',
        'vidsrcme.su',
        'vidsrc-me.ru',
        'vidsrc-me.su',
        'vidsrc-embed.ru',
        'vidsrc-embed.su',
        'vsrc.su',
      ]),
      ext_vixsrc.VixSrc(_fetcher),
      Voe(_fetcher),
      YouTube(_fetcher),
      ExternalUrl(_fetcher), // must remain last
    ];

    _registry = ExtractorRegistry(
      (lvl, msg) => debugPrint('[WS:$lvl] $msg'), extractors);

    // Prioritize fast/reliable sources first to reduce total wait time
    // Order: Most reliable -> Less reliable
    _sources = <Source>[
      // === PRIORITY 1: Fast & Reliable (Tested Working) ===
      VegaMoviesSource(_fetcher),
      VidSrcSource(_fetcher),


      // === PRIORITY 2: Multi-region sources ===
      FourKHDHubSource(_fetcher),
      HDHub4uSource(_fetcher),

      // === PRIORITY 3: Other regions (AL, ES, MX, DE, FR, IT) ===
      // AL
      KokoshkaSource(_fetcher),
      // ES / MX
      CineHDPlusSource(_fetcher),
      CuevanaSource(_fetcher),
      HomeCineSource(_fetcher),
      VerHdLinkSource(_fetcher),
      // DE
      EinschaltenSource(_fetcher),
      KinoGerSource(_fetcher),
      MegaKinoSource(_fetcher),
      MeineCloudSource(_fetcher),
      StreamKisteSource(_fetcher),
      // FR
      FrembedSource(_fetcher),
      FrenchCloudSource(_fetcher),
      MovixSource(_fetcher),
      // IT
      EurostreamingSource(_fetcher),
      MostraGuardaSource(_fetcher),

      // === DISABLED: Blacklisted sources (fail consistently) ===
      // VixSrcSource(_fetcher), // Extractor broken - token/expires/url not found
      // RgShowsSource(_fetcher), // DNS failure - api.rgshows.ru unreachable
    ];

    _resolver =
    StreamResolver((lvl, msg) => debugPrint('[WS:$lvl] $msg'), _registry);
  }

  /// Drop-in replacement for the old remote `getStreams`.
  /// Accepts an IMDb ID (preferred) and optional TMDB ID.
  Future<List<StreamSource>> getStreams({
    required String imdbId,
    bool isMovie = true,
    int? season,
    int? episode,
    int? tmdbId,
  }) async {
    try {
      await init();

      final type = isMovie ? 'movie' : 'series';
      final base = imdbId.split(':').first;
      final Id id;
      if (RegExp(r'^tt\d+$').hasMatch(base)) {
        final raw = isMovie
        ? imdbId
        : '$imdbId:${season ?? 1}:${episode ?? 1}';
        id = ImdbId.fromString(raw);
      } else if (tmdbId != null) {
        final raw = isMovie
        ? '$tmdbId'
        : '$tmdbId:${season ?? 1}:${episode ?? 1}';
        id = TmdbId.fromString(raw);
      } else {
        debugPrint('[WebStreamrService] No valid IMDb/TMDB id for "$imdbId"');
        return [];
      }

      final ctx = await _buildContext(id);

      // Filter out blacklisted sources early
      final filteredSources = _sources.where((source) {
        final sourceName = source.runtimeType.toString().toLowerCase();
        return !_blacklistedSources.any((blacklisted) =>
        sourceName.contains(blacklisted));
      }).toList();

      // Mirror upstream StreamController: only run sources that have at
      // least one country code enabled in the user's config. Avoids wasting
      // network on sources whose results would be filtered out anyway.
      final activeSources = filteredSources
      .where((s) =>
      s.countryCodes.any((cc) => ctx.config.containsKey(cc.name)))
      .toList();
      debugPrint(
        '[WebStreamrService] ${activeSources.length}/${filteredSources.length} sources active for config ${ctx.config.keys.where((k) => k.length == 2 || k == 'multi').toList()}');

      // Process all active sources in parallel (not batched)
      // The resolver internally handles parallelism, but we ensure all
      // enabled sources are tried concurrently
      final res = await _resolver.resolve(ctx, activeSources, type, id);

      final out = <StreamSource>[];
      for (final s in res.streams) {
        final url = (s['url'] ?? s['externalUrl']) as String?;
        if (url == null || url.isEmpty) continue;
        final name = (s['name'] ?? '') as String;
        final title = (s['title'] ?? '') as String;
        final display = name.isNotEmpty ? '$name\n$title' : title;
        Map<String, String>? headers;
        final bh = s['behaviorHints'];
        if (bh is Map &&
          bh['proxyHeaders'] is Map &&
          (bh['proxyHeaders'] as Map)['request'] is Map) {
          headers = Map<String, String>.from(
            (bh['proxyHeaders'] as Map)['request'] as Map);
          }
          // Some sources (e.g. RG Shows / 1shows.app) deliver MPEG-TS
          // segments wrapped in a fake PNG container on TikTok CDN. media_kit
          // can't decode that, so we route the stream through our local HLS
          // proxy with PNG-stripping enabled.
          var finalUrl = url;
        if (Uri.tryParse(url)?.host.contains('1shows.app') ?? false) {
          final ls = LocalServerService();
          if (ls.port != 0) {
            finalUrl = ls.getHlsProxyUrl(url, headers ?? {}, stripMode: 'png');
            // After proxying, the player no longer needs the upstream
            // referer/origin — the local proxy injects them.
            headers = null;
          }
        }
        out.add(StreamSource(
          url: finalUrl,
          title: display,
          type: 'video',
          headers: headers,
        ));
      }
      return out;
    } catch (e, st) {
      debugPrint('[WebStreamrService] Exception: $e\n$st');
      return [];
    }
  }

  Future<Context> _buildContext(Id id) async {
    final config = <String, String>{};
    final enabledCC = await WebStreamrSettings.getEnabledCountryCodes();
    for (final cc in enabledCC) {
      config[cc] = 'on';
    }
    config['multi'] = 'on';

    final mfpUrl = await WebStreamrSettings.getMediaFlowProxyUrl();
    final mfpPwd = await WebStreamrSettings.getMediaFlowProxyPassword();
    if (mfpUrl != null && mfpUrl.isNotEmpty) {
      config['mediaFlowProxyUrl'] = mfpUrl;
      if (mfpPwd != null) config['mediaFlowProxyPassword'] = mfpPwd;
    }

    final flareUrl = await WebStreamrSettings.getFlareSolverrUrl();
    if (flareUrl != null && flareUrl.isNotEmpty) {
      WsEnv.set('FLARESOLVERR_URL', flareUrl);
    }

    for (final exId in await WebStreamrSettings.getDisabledExtractors()) {
      config[disableExtractorConfigKey(exId)] = 'on';
    }
    for (final res in await WebStreamrSettings.getExcludedResolutions()) {
      config[excludeResolutionConfigKey(res)] = 'on';
    }

    // Add shorter timeout configuration for all HTTP requests
    config['requestTimeout'] = '3000'; // 3 seconds in milliseconds

    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('webstreamr_client_ip');

    return Context(
      hostUrl: Uri.parse('http://localhost'),
      id: id.toString(),
      ip: ip,
      config: config,
    );
  }
}
