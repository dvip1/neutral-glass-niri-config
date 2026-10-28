// niri-settings: one window for the desktop's settings (theme, wallpaper, power & idle, theme
// tunables, shortcuts). Styled by ~/.config/theme/out/settings.qss, which `theme apply` generates;
// the window restyles itself when that file changes. One instance: a second launch just
// switches the running one to the requested page.
//
//   niri-settings [appearance|power|theme|shortcuts]
#include "common.h"
#include <QLocalServer>
#include <QLocalSocket>
#include <QJsonArray>
#include <QJsonDocument>
#include <unistd.h>

static const QStringList kPages = {"appearance", "power", "theme", "shortcuts"};

// NIRI_SETTINGS_QSS=file uses another stylesheet (to preview a theme without applying it)
static QString qssPath()
{
    const QString env = qEnvironmentVariable("NIRI_SETTINGS_QSS");
    return env.isEmpty() ? home(".config/theme/out/settings.qss") : env;
}

static QString styleSheet()
{
    QFile f(qssPath());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll()).replace("url(~/", "url(" + QDir::homePath() + "/");
}

// Wayland won't let a window raise itself; ask niri to focus ours.
static void focusSelf()
{
    auto *p = new QProcess;
    QObject::connect(p, &QProcess::finished, p, [p] {
        for (const auto &v : QJsonDocument::fromJson(p->readAllStandardOutput()).array()) {
            const QJsonObject w = v.toObject();
            if (w["pid"].toInteger() == QCoreApplication::applicationPid())
                QProcess::startDetached("niri", {"msg", "action", "focus-window", "--id",
                                                 QString::number(w["id"].toInteger())});
        }
        p->deleteLater();
    });
    p->start("niri", {"msg", "--json", "windows"});
}

int main(int argc, char **argv)
{
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");   // niri draws no title bar either
    QApplication::setStyle("Fusion");
    QApplication app(argc, argv);
    app.setApplicationName("niri-settings");
    app.setDesktopFileName("niri-settings");        // Wayland app-id (niri window rule)
    const QString want = argc > 1 ? QString(argv[1]).toLower() : QString();

    const QString sock = "niri-settings-" + QString::number(getuid());
    {
        QLocalSocket s;
        s.connectToServer(sock);
        if (s.waitForConnected(150)) {
            s.write((want + "\n").toUtf8());
            s.waitForBytesWritten(150);
            return 0;
        }
    }

    app.setStyleSheet(styleSheet());
    // theme.py replaces the file atomically, so watch the folder and compare times
    auto *watch = new QFileSystemWatcher({QFileInfo(qssPath()).absolutePath()}, &app);
    auto stamp = std::make_shared<QDateTime>(QFileInfo(qssPath()).lastModified());
    QObject::connect(watch, &QFileSystemWatcher::directoryChanged, &app, [&app, stamp] {
        const QDateTime t = QFileInfo(qssPath()).lastModified();
        if (t.isValid() && t != *stamp) {
            *stamp = t;
            app.setStyleSheet(styleSheet());
        }
    });

    QWidget win;
    win.setAttribute(Qt::WA_TranslucentBackground);   // niri blurs what shows through
    win.setWindowTitle("Settings");
    auto *outer = new QVBoxLayout(&win);
    outer->setContentsMargins(0, 0, 0, 0);
    auto *root = new QFrame;
    root->setObjectName("root");
    outer->addWidget(root);
    auto *h = new QHBoxLayout(root);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(0);

    auto *side = new QFrame;
    side->setObjectName("side");
    side->setFixedWidth(220);
    auto *sl = new QVBoxLayout(side);
    sl->setContentsMargins(10, 18, 10, 12);
    sl->setSpacing(6);
    auto *brand = new QLabel("Settings");
    brand->setObjectName("brand");
    sl->addWidget(brand);
    auto *nav = new QListWidget;
    nav->setObjectName("nav");
    nav->setFocusPolicy(Qt::NoFocus);
    nav->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    sl->addWidget(nav, 1);
    auto *status = new QLabel;
    status->setObjectName("status");
    status->setWordWrap(true);
    sl->addWidget(status);
    h->addWidget(side);

    auto *stack = new QStackedWidget;
    h->addWidget(stack, 1);
    const QList<std::tuple<QString, QString, QWidget *(*)()>> pages = {
        {QString::fromUtf8("\U000F03D8"), "Appearance", makeAppearancePage},
        {QString::fromUtf8("\U000F0079"), "Power & Idle", makePowerPage},
        {QString::fromUtf8("\U000F062E"), "Theme Details", makeTuningPage},
        {QString::fromUtf8("\U000F030C"), "Shortcuts & More", makeMiscPage},
    };
    nav->setIconSize(QSize(18, 18));
    for (const auto &[icon, title, make] : pages) {
        nav->addItem(title);
        stack->addWidget(new QWidget);              // built the first time it is shown
    }
    // Nerd Font glyphs drawn as icons, in the list's text colour (redrawn when the stylesheet changes it)
    auto paintIcons = [nav, pages] {
        const qreal dpr = nav->devicePixelRatioF();
        QFont f("Cascadia Code NF");
        f.setPixelSize(17);
        for (int i = 0; i < nav->count(); ++i) {
            QPixmap pm(QSize(18, 18) * dpr);
            pm.setDevicePixelRatio(dpr);
            pm.fill(Qt::transparent);
            QPainter p(&pm);
            p.setFont(f);
            p.setPen(nav->palette().color(QPalette::Text));
            p.drawText(QRectF(0, 0, 18, 18), Qt::AlignCenter, std::get<0>(pages[i]));
            p.end();
            nav->item(i)->setIcon(QIcon(pm));
        }
    };
    paintIcons();
    new OnEvent(nav, QEvent::PaletteChange, paintIcons);
    auto built = std::make_shared<QSet<int>>();
    QObject::connect(nav, &QListWidget::currentRowChanged, stack, [=](int i) {
        if (i < 0)
            return;
        if (!built->contains(i)) {
            built->insert(i);
            QWidget *old = stack->widget(i);
            stack->insertWidget(i, std::get<2>(pages[i])());
            stack->removeWidget(old);
            old->deleteLater();
        }
        stack->setCurrentIndex(i);
    });
    nav->setCurrentRow(qMax(0, kPages.indexOf(want)));

    auto *T = Theme::get();
    auto *clear = new QTimer(&win);
    clear->setSingleShot(true);
    QObject::connect(clear, &QTimer::timeout, status, &QLabel::clear);
    QObject::connect(T, &Theme::busyChanged, status, [status, clear](bool busy) {
        if (busy) {
            clear->stop();
            status->setText("Applying…");
        } else if (status->text() == "Applying…") {
            status->clear();
        }
    });
    QObject::connect(T, &Theme::failed, status, [status, clear](const QString &msg) {
        status->setText(msg);
        clear->start(8000);
    });
    T->refresh();

    QLocalServer::removeServer(sock);
    QLocalServer server;
    server.listen(sock);
    QObject::connect(&server, &QLocalServer::newConnection, &server, [&] {
        QLocalSocket *c = server.nextPendingConnection();
        QObject::connect(c, &QLocalSocket::readyRead, c, [c, nav] {
            const int i = kPages.indexOf(QString::fromUtf8(c->readAll()).trimmed());
            if (i >= 0)
                nav->setCurrentRow(i);
            focusSelf();
            c->deleteLater();
        });
    });

    win.resize(980, 680);
    win.show();
    return app.exec();
}
