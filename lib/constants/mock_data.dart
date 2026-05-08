class HistoryItem {
  final int id;
  final String title;
  final String size;
  final String date;
  const HistoryItem({
    required this.id,
    required this.title,
    required this.size,
    required this.date,
  });
}

const mockHistory = [
  HistoryItem(id: 1, title: '2024年度财务报告.pdf', size: '2.4 MB', date: '10分钟前'),
  HistoryItem(
    id: 2,
    title: 'React 设计模式指南.pdf',
    size: '15.8 MB',
    date: '昨天 14:20',
  ),
  HistoryItem(id: 3, title: 'UI/UX 规范手册 v2.pdf', size: '5.1 MB', date: '3天前'),
];
