#include "common.h"
#include <QJsonDocument>

QString home(const QString &rel) { return QDir::homePath() + "/" + rel; }
QString localBin(const QString &name) { return home(".local/bin/" + name); }

void spawnDetached(const QStringList &cmd)
{
    QProcess::startDetached("niri", QStringList {"msg", "action", "spawn", "--"} + cmd);
}

void openInEditor(const QString &file)
{
    spawnDetached({"kitty", "-o", "hide_window_decorations=yes", "--title", QFileInfo(file).fileName(), "nvim", file});
}

void roundPopup(QComboBox *combo)
{
    // The dropdown is its own (popup) window: make it frameless and see-through so the
    // stylesheet's rounded corners show instead of a square box.
    QWidget *w = combo->view()->window();
    w->setWindowFlags(Qt::Popup | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
    w->setAttribute(Qt::WA_TranslucentBackground);
}

// ---------- Switch ----------
Switch::Switch(QWidget *parent) : QAbstractButton(parent)
{
    setCheckable(true);
    setCursor(Qt::PointingHandCursor);
    setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    anim_ = new QPropertyAnimation(this, "knobPos", this);
    anim_->setDuration(150);
    anim_->setEasingCurve(QEasingCurve::OutCubic);
    connect(this, &QAbstractButton::toggled, this, [this](bool on) {
        anim_->stop();
        anim_->setEndValue(on ? 1.0 : 0.0);
        anim_->start();
    });
}

void Switch::setCheckedQuiet(bool on)
{
    QSignalBlocker b(this);
    setChecked(on);
    anim_->stop();
    setKnobPos(on ? 1 : 0);
}

static QColor mix(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t, a.alphaF() + (b.alphaF() - a.alphaF()) * t);
}

void Switch::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    const QRectF r = QRectF(rect()).adjusted(0.5, 0.5, -0.5, -0.5);
    p.setBrush(mix(off_, on_, pos_));
    p.drawRoundedRect(r, r.height() / 2, r.height() / 2);
    const qreal d = r.height() - 6;
    p.setBrush(mix(knob_, knobOn_, pos_));
    p.drawEllipse(QRectF(r.x() + 3 + pos_ * (r.width() - 6 - d), r.y() + 3, d, d));
}

// ---------- ThemeCard ----------
ThemeCard::ThemeCard(const QString &name, const QString &desc, const QList<QColor> &sw, QWidget *parent)
    : QAbstractButton(parent), name_(name), desc_(desc), sw_(sw)
{
    setCheckable(true);
    setCursor(Qt::PointingHandCursor);
    setToolTip(desc);
    setMinimumSize(170, 92);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    while (sw_.size() < 4)
        sw_ << QColor(Qt::gray);
}

void ThemeCard::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    const QColor bg = sw_[0], surface = sw_[1], fg = sw_[2], accent = sw_[3];
    const QRectF r = QRectF(rect()).adjusted(2, 2, -2, -2);
    p.setPen(Qt::NoPen);
    p.setBrush(bg);
    p.drawRoundedRect(r, 10, 10);
    if (isChecked() || underMouse()) {
        QColor c = isChecked() ? accent_ : border_;
        p.setPen(QPen(c, isChecked() ? 2.5 : 1.5));
    } else {
        p.setPen(QPen(border_, 1));
    }
    p.setBrush(Qt::NoBrush);
    p.drawRoundedRect(r, 10, 10);

    // a little "window": surface panel with an accent pill
    const QRectF panel(r.right() - 64, r.top() + 12, 50, r.height() - 24);
    p.setPen(Qt::NoPen);
    p.setBrush(surface);
    p.drawRoundedRect(panel, 6, 6);
    p.setBrush(accent);
    p.drawRoundedRect(QRectF(panel.left() + 8, panel.top() + 8, panel.width() - 16, 8), 4, 4);
    QColor line = fg;
    line.setAlphaF(0.35);
    p.setBrush(line);
    p.drawRoundedRect(QRectF(panel.left() + 8, panel.top() + 22, panel.width() - 22, 4), 2, 2);
    p.drawRoundedRect(QRectF(panel.left() + 8, panel.top() + 31, panel.width() - 16, 4), 2, 2);

    QFont f = font();
    f.setWeight(QFont::DemiBold);
    p.setFont(f);
    p.setPen(fg);
    const QRectF text(r.left() + 14, r.top() + 12, panel.left() - r.left() - 22, r.height() - 24);
    p.drawText(text, Qt::AlignLeft | Qt::AlignTop, name_);
    f.setWeight(QFont::Normal);
    f.setPixelSize(qMax(10, f.pixelSize() > 0 ? f.pixelSize() - 2 : 11));
    p.setFont(f);
    QColor dim = fg;
    dim.setAlphaF(0.7);
    p.setPen(dim);
    const QRectF descBox = text.adjusted(0, QFontMetricsF(font()).height() + 4, 0, 0);
    p.drawText(descBox, Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap, desc_);
}

// ---------- Stepper ----------
Stepper::Stepper(double min, double max, double step, int decimals, const QString &suffix, QWidget *parent)
    : QWidget(parent)
{
    auto *lay = new QHBoxLayout(this);
    lay->setContentsMargins(0, 0, 0, 0);
    lay->setSpacing(4);
    auto *minus = new QPushButton("−");
    auto *plus = new QPushButton("+");
    for (auto *b : {minus, plus}) {
        b->setObjectName("step");
        b->setFixedSize(30, 30);
        b->setAutoRepeat(true);
        b->setFocusPolicy(Qt::NoFocus);
    }
    box_ = new QDoubleSpinBox;
    box_->setRange(min, max);
    box_->setSingleStep(step);
    box_->setDecimals(decimals);
    box_->setSuffix(suffix);
    box_->setButtonSymbols(QAbstractSpinBox::NoButtons);
    box_->setAlignment(Qt::AlignCenter);
    box_->setFixedWidth(84);
    box_->setKeyboardTracking(false);
    lay->addWidget(minus);
    lay->addWidget(box_);
    lay->addWidget(plus);
    connect(minus, &QPushButton::clicked, box_, &QDoubleSpinBox::stepDown);
    connect(plus, &QPushButton::clicked, box_, &QDoubleSpinBox::stepUp);
    connect(box_, &QDoubleSpinBox::valueChanged, this, &Stepper::valueChanged);
}

void Stepper::setValueQuiet(double v)
{
    QSignalBlocker b(box_);
    box_->setValue(v);
}

// ---------- PercentSlider ----------
PercentSlider::PercentSlider(int min, int max, QWidget *parent) : QWidget(parent)
{
    auto *lay = new QHBoxLayout(this);
    lay->setContentsMargins(0, 0, 0, 0);
    lay->setSpacing(10);
    slider_ = new QSlider(Qt::Horizontal);
    slider_->setRange(min, max);
    slider_->setFixedWidth(180);
    label_ = new QLabel;
    label_->setObjectName("rowSub");
    label_->setFixedWidth(40);
    label_->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    lay->addWidget(slider_);
    lay->addWidget(label_);
    connect(slider_, &QSlider::valueChanged, this, [this](int v) {
        label_->setText(QString::number(v) + " %");
        emit valueChanged(v);
    });
}

void PercentSlider::setValueQuiet(int v)
{
    QSignalBlocker b(slider_);
    slider_->setValue(v);
    label_->setText(QString::number(v) + " %");
}

// ---------- Card / Page ----------
Card::Card(QWidget *parent) : QFrame(parent)
{
    setObjectName("card");
    lay_ = new QVBoxLayout(this);
    lay_->setContentsMargins(0, 4, 0, 4);
    lay_->setSpacing(0);
}

void Card::addWidget(QWidget *w)
{
    if (items_++) {
        auto *sep = new QFrame;
        sep->setObjectName("sep");
        sep->setFixedHeight(1);
        lay_->addWidget(sep);
    }
    lay_->addWidget(w);
}

QWidget *Card::addRow(const QString &title, const QString &sub, QWidget *control, QWidget *extra)
{
    auto *row = new QWidget;
    row->setObjectName("row");
    auto *h = new QHBoxLayout(row);
    h->setContentsMargins(16, 9, 12, 9);
    h->setSpacing(10);
    auto *labels = new QVBoxLayout;
    labels->setSpacing(1);
    auto *t = new QLabel(title);
    t->setObjectName("rowTitle");
    labels->addWidget(t);
    if (!sub.isEmpty()) {
        auto *s = new QLabel(sub);
        s->setObjectName("rowSub");
        s->setWordWrap(true);
        labels->addWidget(s);
    }
    h->addLayout(labels, 1);
    if (extra)
        h->addWidget(extra);
    if (control)
        h->addWidget(control);
    row->setMinimumHeight(52);
    addWidget(row);
    return row;
}

Page::Page(const QString &title, QWidget *parent) : QScrollArea(parent)
{
    setWidgetResizable(true);
    setFrameShape(QFrame::NoFrame);
    setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    auto *inner = new QWidget;
    inner->setObjectName("pageInner");
    body = new QVBoxLayout(inner);
    body->setContentsMargins(28, 22, 28, 28);
    body->setSpacing(10);
    auto *t = new QLabel(title);
    t->setObjectName("pageTitle");
    body->addWidget(t);
    setWidget(inner);
    viewport()->setAutoFillBackground(false);
    inner->setAutoFillBackground(false);
}

QLabel *Page::section(const QString &title)
{
    auto *l = new QLabel(title);
    l->setObjectName("sectionTitle");
    body->addWidget(l);
    return l;
}

Card *Page::card()
{
    auto *c = new Card;
    body->addWidget(c);
    return c;
}

// ---------- Theme runner ----------
Theme *Theme::get()
{
    static Theme *t = new Theme;
    return t;
}

void Theme::run(const QStringList &args)
{
    if (args.isEmpty())
        dirty_ = true;
    else
        queue_ << args;
    if (!proc_)
        next();
}

void Theme::next()
{
    QStringList args;
    bool reading = false;
    if (!queue_.isEmpty()) {
        args = queue_.takeFirst();
        dirty_ = true;
    } else if (dirty_) {
        args = {"json"};
        reading = true;
        dirty_ = false;
    } else {
        emit busyChanged(false);
        return;
    }
    if (!reading)
        emit busyChanged(true);
    proc_ = new QProcess(this);
    connect(proc_, &QProcess::finished, this, [this, reading, args](int code, QProcess::ExitStatus) {
        const QByteArray out = proc_->readAllStandardOutput(), err = proc_->readAllStandardError();
        proc_->deleteLater();
        proc_ = nullptr;
        if (code != 0)
            emit failed(QString::fromUtf8(err).trimmed().section('\n', -1));
        else if (reading) {
            const auto doc = QJsonDocument::fromJson(out);
            if (doc.isObject()) {
                data = doc.object();
                emit changed();
            }
        }
        next();
    });
    proc_->start(localBin("theme"), args);
}
