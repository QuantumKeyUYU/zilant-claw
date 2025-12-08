class AppStrings {
  static const String title = 'Digital Defender';
  static const String poweredBy = 'Powered by Zilant Core';
  static const String blockedRequestsLabel = 'Заблокировано запросов: ';
  static const String protectionInfoLink = 'Как работает защита?';
  static const String protectionOn = 'Дракон охраняет тебя. Защита включена.';
  static const String protectionTurningOn = 'Включаем защиту…';
  static const String protectionTurningOff = 'Выключаем защиту…';
  static const String protectionError = 'Произошла ошибка. Защита не включена.';
  static const String protectionOff = 'Дракон отдыхает. Защита выключена.';
  static const String progressTurningOn =
      'Запрашиваем доступ к VPN и поднимаем защиту...';
  static const String progressTurningOff =
      'Останавливаем защиту и закрываем VPN...';
  static const String progressError =
      'Проверьте разрешения VPN или повторите попытку.';
  static const String infoTitle = 'Как это работает и как мы защищаем';
  static const String infoIntro =
      'Фильтрация трафика происходит локально на устройстве через VPN-службу. '
      'Ваш трафик не отправляется на наши сервера.';
  static const String infoBlocklist =
      'Мы блокируем домены из встроенного списка (реклама, трекеры, потенциально вредоносные сайты).';
  static const String infoPrivacy =
      'Приложение не собирает личные данные и не отправляет никакую аналитику наружу.';
  static const String infoControl =
      'Вы в любой момент можете отключить защиту — она не внедряется в системные файлы.';

  static const String protectionEnabled = 'Защита: включена';
  static const String protectionDisabled = 'Защита: выключена';
  static const String protectionUnknown = 'Статус защиты неизвестен';
  static const String vpnActive = 'VPN активен';
  static const String vpnInactive = 'VPN не запущен';
  static const String protectionHintOn =
      'Мы блокируем трекеры и лишнюю аналитику из списка.';
  static const String protectionHintOff = 'Трафик идёт напрямую — без фильтра.';
  static const String protectionFailOpenWarning =
      'Фильтр временно ослаблен — DNS не отвечает, чтобы не ломать интернет мы пропускаем трафик без блокировки.';
  static const String blockedCompact = 'Заблокировано: %s за сеанс / %s всего';
  static const String refreshStats = 'Обновить данные';
  static const String resetStats = 'Сбросить статистику';
  static const String details = 'Подробнее';
  static const String recentTitle = 'Недавние заблокированные домены';
  static const String recentPreview = 'Недавние заблокированные домены: %d (смотреть)';
  static const String nothingBlocked =
      'Пока ничего не заблокировано — вы в чистом интернете 😌';
  static const String noRecentBlocks = 'Нет свежих блокировок';
  static const String yesterday = 'вчера';
  static const String daysAgoSuffix = 'дн. назад';
  static const String grantVpnPermission = 'Выдать разрешение';
  static const String retryStart = 'Попробовать ещё раз';
  static const String statsError = 'Не удалось обновить статистику.';
  static const String statsPageTitle = 'Статистика и домены';
  static const String protectionModeLabel = 'Режим защиты';
  static const String protectionModeLight = 'Лёгкий';
  static const String protectionModeStandard = 'Стандарт';
  static const String protectionModeStrict = 'Жёсткий';
  static const String protectionModeChanged = 'Режим защиты: %s';
  static const String protectionModeHintLight =
      'Режет только трекеры и аналитику, почти ничего не ломает';
  static const String protectionModeHintStandard =
      'Баланс защиты и стабильности, блокирует рекламу и трекеры';
  static const String protectionModeHintStrict =
      'Максимальная защита: агрессивные блокировки, сайты и приложения могут работать некорректно';
  static const String modeStatus = 'Режим: %s';
  static const String filterStatusActive = 'Фильтр активен';
  static const String filterStatusFailOpen =
      'Фильтр временно отключён (DNS-проблема)';
  static const String totalLabel = 'Всего';
  static const String sessionLabel = 'За сеанс';
  static const String clearRecent = 'Очистить список';
  static const String statsHeaderTitle = 'Статистика и домены';
  static const String recentEmpty =
      'Пока ничего не заблокировано — вы в чистом интернете 😌';
}
