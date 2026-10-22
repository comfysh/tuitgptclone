// Texts for the widget area (en / uz Latin / ru). Merged into S by strings.dart.
//
// Used by the Android home-screen widget "TuitMate · Today": the app saves them
// (lib/services/home_widget_service.dart) and the Kotlin provider shows them, so
// they are short and use placeholders the provider fills in ({time}).
const Map<String, Map<String, String>> widgetStrings = {
  'en': {
    'wgClassesToday': 'classes today',
    'wgOpenTasks': 'open tasks',
    'wgNbHours': 'NB hours',
    'wgNoMore': 'No more classes today',
    'wgFreeDay': 'No classes today',
    'wgTomorrowAt': 'Tomorrow, {time}',
    'wgNoneThisWeek': 'No classes in the next 7 days',
    'wgDueToday': 'today, {time}',
    'wgDueTomorrow': 'tomorrow, {time}',
    'wgNoTasks': 'No open tasks',
    'wgOpenApp': 'Open TuitMate to see your day',
    'wgSync': 'Open TuitMate to sync',
  },
  'uz': {
    'wgClassesToday': 'bugungi dars',
    'wgOpenTasks': 'topshiriqlar',
    'wgNbHours': 'NB soatlari',
    'wgNoMore': "Bugun boshqa dars yo'q",
    'wgFreeDay': "Bugun dars yo'q",
    'wgTomorrowAt': 'Ertaga, {time}',
    'wgNoneThisWeek': "Keyingi 7 kunda dars yo'q",
    'wgDueToday': 'bugun, {time}',
    'wgDueTomorrow': 'ertaga, {time}',
    'wgNoTasks': "Ochiq topshiriqlar yo'q",
    'wgOpenApp': "Kuningizni ko'rish uchun TuitMate'ni oching",
    'wgSync': "Yangilash uchun TuitMate'ni oching",
  },
  'ru': {
    'wgClassesToday': 'пар сегодня',
    'wgOpenTasks': 'задания',
    'wgNbHours': 'часов НБ',
    'wgNoMore': 'Сегодня пар больше нет',
    'wgFreeDay': 'Сегодня пар нет',
    'wgTomorrowAt': 'Завтра, {time}',
    'wgNoneThisWeek': 'В ближайшие 7 дней пар нет',
    'wgDueToday': 'сегодня, {time}',
    'wgDueTomorrow': 'завтра, {time}',
    'wgNoTasks': 'Нет открытых заданий',
    'wgOpenApp': 'Откройте TuitMate, чтобы увидеть свой день',
    'wgSync': 'Откройте TuitMate для обновления',
  },
};
