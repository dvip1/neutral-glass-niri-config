// Appearance: dark style, theme picker, wallpaper.
#include "common.h"
#include <QJsonArray>
#include <atomic>

static const QStringList kImages = {"*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"};

static QString currentWallpaper()
{
    QFile f(home(".config/niri/wallpaper"));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

static QString pretty(const QString &dir)
{
    QString h = QDir::homePath();
    return dir.startsWith(h) ? "~" + dir.mid(h.size()) : dir;
}

// A rounded, centre-cropped thumbnail, cached in ~/.cache/niri-settings/thumbs. Runs on a worker thread.
static QImage thumbnail(const QString &path, const QSize &size, qreal radius)
{
    const QFileInfo fi(path);
    const QByteArray key = QCryptographicHash::hash(
        (path + "|" + QString::number(fi.lastModified().toSecsSinceEpoch()) + "|" + QString::number(size.width()))
            .toUtf8(),
        QCryptographicHash::Md5).toHex();
    const QString cache = home(".cache/niri-settings/thumbs/") + key + ".png";
    QImage img;
    if (img.load(cache))
        return img;
    QImageReader reader(path);
    reader.setAutoTransform(true);
    if (reader.size().isValid())
        reader.setScaledSize(reader.size().scaled(size, Qt::KeepAspectRatioByExpanding));
    QImage src = reader.read();
    if (src.isNull())
        return {};
    if (src.size() != size)
        src = src.scaled(size, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    QImage out(size, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter p(&out);
    p.setRenderHint(QPainter::Antialiasing);
    QPainterPath clip;
    clip.addRoundedRect(QRectF(QPointF(0, 0), QSizeF(size)), radius, radius);
    p.setClipPath(clip);
    p.drawImage(QPoint((size.width() - src.width()) / 2, (size.height() - src.height()) / 2), src);
    p.end();
    QDir().mkpath(QFileInfo(cache).path());
    out.save(cache);
    return out;
}

QWidget *makeAppearancePage()
{
    auto *page = new Page("Appearance");
    auto *T = Theme::get();

    // ---- style
    auto *style = page->card();
    auto *dark = new Switch;
    style->addRow("Dark style", "The shell, kitty and apps follow it", dark);
    QObject::connect(dark, &QAbstractButton::toggled, dark, [T](bool on) { T->run({on ? "dark" : "light"}); });

    // ---- themes
    page->section("Theme");
    auto *gridHost = new QWidget;
    auto *grid = new QGridLayout(gridHost);
    grid->setContentsMargins(0, 0, 0, 0);
    grid->setSpacing(10);
    page->body->addWidget(gridHost);
    auto *group = new QButtonGroup(gridHost);
    auto cards = std::make_shared<QList<ThemeCard *>>();
    auto cols = std::make_shared<int>(0);
    auto reflow = [=](bool force) {
        const int n = qMax(1, (gridHost->width() + 10) / 200);
        if (n == *cols && !force)
            return;
        *cols = n;
        while (QLayoutItem *it = grid->takeAt(0))
            delete it;
        for (int i = 0; i < cards->size(); ++i)
            grid->addWidget(cards->at(i), i / n, i % n);
    };
    new OnEvent(gridHost, QEvent::Resize, [=] { reflow(false); });

    auto fill = [=] {
        const QString mode = T->data["mode"].toString(), cur = T->data["current"].toString();
        dark->setCheckedQuiet(mode == "dark");
        qDeleteAll(*cards);
        cards->clear();
        for (const auto &v : T->data["themes"].toArray()) {
            const QJsonObject o = v.toObject();
            const QString name = o["name"].toString();
            QList<QColor> sw;
            for (const auto &c : o["swatches"].toObject()[mode].toArray())
                sw << QColor(c.toString());
            auto *card = new ThemeCard(name, o["description"].toString(), sw);
            card->setChecked(name == cur);
            group->addButton(card);
            QObject::connect(card, &QAbstractButton::clicked, card, [T, name] {
                if (T->data["current"].toString() != name)
                    T->run({"set", name});
            });
            cards->append(card);
        }
        reflow(true);
    };
    QObject::connect(T, &Theme::changed, page, fill);
    if (!T->data.isEmpty())
        fill();

    // ---- wallpaper
    page->section("Wallpaper");
    auto *wcard = page->card();
    auto *folder = new QComboBox;
    folder->setMinimumWidth(230);
    roundPopup(folder);
    auto *other = new QPushButton("Other folder…");
    wcard->addRow("Folder", QString(), folder, other);

    auto *walls = new QListWidget;
    walls->setObjectName("walls");
    walls->setViewMode(QListView::IconMode);
    walls->setMovement(QListView::Static);
    walls->setResizeMode(QListView::Adjust);
    walls->setUniformItemSizes(true);
    walls->setIconSize(QSize(160, 100));
    walls->setGridSize(QSize(176, 116));
    walls->setSpacing(0);
    walls->setMinimumHeight(360);
    walls->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    walls->setSelectionMode(QAbstractItemView::SingleSelection);
    auto *wrap = new QWidget;
    auto *wl = new QVBoxLayout(wrap);
    wl->setContentsMargins(10, 8, 6, 8);
    wl->addWidget(walls);
    wcard->addWidget(wrap);

    // folders: the current wallpaper's, then every picture folder in ~/Pictures that has images
    const QString cur = currentWallpaper();
    QStringList dirs;
    if (!cur.isEmpty())
        dirs << QFileInfo(cur).absolutePath();
    QDir pics(home("Pictures"));
    for (const QString &d : pics.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        const QString full = pics.filePath(d);
        if (d == "Screenshots" || dirs.contains(full))
            continue;
        if (!QDir(full).entryList(kImages, QDir::Files).isEmpty())
            dirs << full;
    }
    for (const QString &d : dirs)
        folder->addItem(pretty(d), d);

    static QThreadPool pool;
    pool.setMaxThreadCount(qMax(2, QThread::idealThreadCount() / 2));
    auto gen = std::make_shared<std::atomic<int>>(0);

    auto load = [=](const QString &dir) {
        const int g = ++*gen;
        pool.clear();
        walls->clear();
        const qreal dpr = walls->devicePixelRatioF();
        const QSize px(qRound(160 * dpr), qRound(100 * dpr));
        QPixmap blank(px);
        blank.fill(Qt::transparent);
        blank.setDevicePixelRatio(dpr);
        const QString now = currentWallpaper();
        const QDir d(dir);
        for (const QString &f : d.entryList(kImages, QDir::Files, QDir::Name)) {
            const QString path = d.filePath(f);
            auto *item = new QListWidgetItem(QIcon(blank), QString());
            item->setData(Qt::UserRole, path);
            item->setToolTip(f);
            item->setSizeHint(QSize(176, 116));
            walls->addItem(item);
            if (path == now) {
                item->setSelected(true);
                walls->scrollToItem(item, QAbstractItemView::PositionAtCenter);
            }
            pool.start([=] {
                if (*gen != g)
                    return;
                QImage img = thumbnail(path, px, 8 * dpr);
                if (img.isNull())
                    return;
                QMetaObject::invokeMethod(walls, [=] {
                    if (*gen != g)
                        return;
                    QPixmap pm = QPixmap::fromImage(img);
                    pm.setDevicePixelRatio(dpr);
                    item->setIcon(QIcon(pm));
                }, Qt::QueuedConnection);
            });
        }
    };

    QObject::connect(folder, &QComboBox::currentIndexChanged, walls, [=](int i) {
        if (i >= 0)
            load(folder->itemData(i).toString());
    });
    QObject::connect(other, &QPushButton::clicked, page, [=] {
        const QString d = QFileDialog::getExistingDirectory(page, "Wallpaper folder", home("Pictures"),
                                                            QFileDialog::ShowDirsOnly | QFileDialog::DontUseNativeDialog);
        if (d.isEmpty())
            return;
        int i = folder->findData(d);
        if (i < 0) {
            folder->addItem(pretty(d), d);
            i = folder->count() - 1;
        }
        folder->setCurrentIndex(i);
    });
    QObject::connect(walls, &QListWidget::itemClicked, walls, [](QListWidgetItem *item) {
        spawnDetached({localBin("setwall"), item->data(Qt::UserRole).toString()});
    });
    if (folder->count())
        QTimer::singleShot(0, walls, [=] { load(folder->currentData().toString()); });

    page->body->addStretch(1);
    return page;
}
