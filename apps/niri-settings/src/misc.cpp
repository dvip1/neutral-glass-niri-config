// Shortcuts & misc: do not disturb, restart the shell, config files, a searchable list of niri's key binds.
#include "common.h"
#include <QJsonDocument>
#include <signal.h>

static bool dndOn()
{
    QFile f(home(".local/state/quickshell/notifications.json"));
    if (!f.open(QIODevice::ReadOnly))
        return false;
    return QJsonDocument::fromJson(f.readAll()).object()["dnd"].toBool();
}

QWidget *makeMiscPage()
{
    auto *page = new Page("Shortcuts & More");
    auto *T = Theme::get();

    // ---- shell
    page->section("Shell");
    auto *shell = page->card();
    auto *dnd = new Switch;
    dnd->setCheckedQuiet(dndOn());
    shell->addRow("Do not disturb", "Only critical notifications pop up", dnd);
    QObject::connect(dnd, &QAbstractButton::toggled, page, [dnd](bool on) {
        if (on != dndOn())
            QProcess::startDetached("qs", {"ipc", "call", "notifications", "dnd"});
        QTimer::singleShot(500, dnd, [dnd] { dnd->setCheckedQuiet(dndOn()); });
    });
    auto *restart = new QPushButton("Restart");
    shell->addRow("Restart the shell", "Bar, notifications, launcher (Quickshell)", restart);
    QObject::connect(restart, &QPushButton::clicked, page, [] {
        QProcess pg;
        pg.start("pgrep", {"-x", "qs"});
        pg.waitForFinished(1000);
        for (const QByteArray &pid : pg.readAllStandardOutput().split('\n'))
            if (!pid.trimmed().isEmpty())
                ::kill(pid.trimmed().toInt(), SIGTERM);
        QTimer::singleShot(700, [] { spawnDetached({"qs"}); });
    });

    // ---- config files
    page->section("Config files");
    auto *files = page->card();
    auto addFile = [&](const QString &title, const QString &sub, std::function<QString()> path) {
        auto *b = new QPushButton("Open");
        files->addRow(title, sub, b);
        QObject::connect(b, &QPushButton::clicked, page, [path] { openInEditor(path()); });
    };
    addFile("niri", "~/.config/niri/config.kdl: keys, outputs, window rules",
            [] { return home(".config/niri/config.kdl"); });
    addFile("Current theme", "Its colours and overrides",
            [T] { return home(".config/theme/themes/" + T->data["current"].toString() + ".toml"); });
    addFile("Shared theme defaults", "~/.config/theme/theme.toml: formulas every theme uses",
            [] { return home(".config/theme/theme.toml"); });
    addFile("Power & idle", "~/.config/power/power.conf", [] { return home(".config/power/power.conf"); });

    // ---- key binds
    page->section("Keyboard shortcuts");
    auto *keys = page->card();
    auto *search = new QLineEdit;
    search->setPlaceholderText("Search shortcuts");
    search->setClearButtonEnabled(true);
    auto *tree = new KeyList;
    tree->setObjectName("keys");
    tree->setColumnCount(2);
    tree->setHeaderHidden(true);
    tree->setRootIsDecorated(false);
    tree->setIndentation(0);
    tree->setSelectionMode(QAbstractItemView::NoSelection);
    tree->setFocusPolicy(Qt::NoFocus);
    tree->setMinimumHeight(440);
    tree->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    auto *wrap = new QWidget;
    auto *wl = new QVBoxLayout(wrap);
    wl->setContentsMargins(12, 12, 8, 8);
    wl->setSpacing(8);
    wl->addWidget(search);
    wl->addWidget(tree);
    keys->addWidget(wrap);

    auto *proc = new QProcess(page);
    QObject::connect(proc, &QProcess::finished, page, [=] {
        QTreeWidgetItem *sec = nullptr;
        static const QRegularExpression head("^== (.*) ==$"), entry("^\\s{2}(\\S.*?)\\s{2,}(\\S.*)$");
        for (const QString &line : QString::fromUtf8(proc->readAllStandardOutput()).split('\n')) {
            if (auto m = head.match(line); m.hasMatch()) {
                sec = new QTreeWidgetItem(tree, {m.captured(1)});
                sec->setFirstColumnSpanned(true);
                QFont f = tree->font();
                f.setWeight(QFont::DemiBold);
                sec->setFont(0, f);
                sec->setData(0, Qt::UserRole, "section");
                sec->setExpanded(true);
            } else if (auto m = entry.match(line); m.hasMatch() && sec) {
                new QTreeWidgetItem(sec, {m.captured(1), m.captured(2)});
            }
        }
        tree->expandAll();
        tree->resizeColumnToContents(0);
        tree->setColumnWidth(0, qMin(tree->columnWidth(0) + 24, 260));
    });
    proc->start(localBin("shortcuts"), {"--print"});

    QObject::connect(search, &QLineEdit::textChanged, tree, [tree](const QString &q) {
        for (int i = 0; i < tree->topLevelItemCount(); ++i) {
            QTreeWidgetItem *sec = tree->topLevelItem(i);
            const bool secHit = sec->text(0).contains(q, Qt::CaseInsensitive);
            int shown = 0;
            for (int j = 0; j < sec->childCount(); ++j) {
                QTreeWidgetItem *it = sec->child(j);
                const bool hit = q.isEmpty() || secHit || it->text(0).contains(q, Qt::CaseInsensitive) ||
                                 it->text(1).contains(q, Qt::CaseInsensitive);
                it->setHidden(!hit);
                shown += hit;
            }
            sec->setHidden(shown == 0);
        }
    });

    page->body->addStretch(1);
    return page;
}
