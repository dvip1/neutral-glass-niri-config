// Shared bits of niri-settings: small helpers, the custom widgets, and the `theme` runner.
#pragma once
#include <QtWidgets>
#include <QJsonObject>

QString home(const QString &rel);              // "$HOME/rel"
QString localBin(const QString &name);         // ~/.local/bin/name (niri's PATH lacks it)
void spawnDetached(const QStringList &cmd);    // through niri, so it lives in niri's scope, not ours
void openInEditor(const QString &file);        // nvim in a glass kitty window
void roundPopup(QComboBox *combo);             // rounded, see-through dropdown list

// GNOME-style on/off switch. Colours come from the stylesheet (qproperty-*).
class Switch : public QAbstractButton {
    Q_OBJECT
    Q_PROPERTY(QColor onColor MEMBER on_)
    Q_PROPERTY(QColor offColor MEMBER off_)
    Q_PROPERTY(QColor knobColor MEMBER knob_)
    Q_PROPERTY(QColor knobOnColor MEMBER knobOn_)
    Q_PROPERTY(qreal knobPos READ knobPos WRITE setKnobPos)
public:
    explicit Switch(QWidget *parent = nullptr);
    QSize sizeHint() const override { return {38, 22}; }   // the shell's Switch.qml
    qreal knobPos() const { return pos_; }
    void setKnobPos(qreal p) { pos_ = p; update(); }
    void setCheckedQuiet(bool on);             // no toggled() signal, no animation
protected:
    void paintEvent(QPaintEvent *) override;
private:
    QColor on_ {"#3584e4"}, off_ {"#55555555"}, knob_ {Qt::white}, knobOn_ {Qt::white};
    qreal pos_ = 0;
    QPropertyAnimation *anim_;
};

// A theme preview: painted in the theme's own colours (bg, surface, fg, accent).
class ThemeCard : public QAbstractButton {
    Q_OBJECT
    Q_PROPERTY(QColor accent MEMBER accent_)
    Q_PROPERTY(QColor border MEMBER border_)
    Q_PROPERTY(int radius MEMBER radius_)
    Q_PROPERTY(int innerRadius MEMBER inner_)
public:
    ThemeCard(const QString &name, const QString &desc, const QList<QColor> &swatches, QWidget *parent = nullptr);
    QSize sizeHint() const override { return {200, 92}; }
    QString name() const { return name_; }
protected:
    void paintEvent(QPaintEvent *) override;
    void enterEvent(QEnterEvent *) override { update(); }
    void leaveEvent(QEvent *) override { update(); }
private:
    QString name_, desc_;
    QList<QColor> sw_;
    QColor accent_ {"#ffffff"}, border_ {"#33ffffff"};
    int radius_ = 12, inner_ = 7;
};

// The wallpaper grid. thumbRadius comes from the stylesheet; thumbnails are redrawn when it changes.
class Walls : public QListWidget {
    Q_OBJECT
    Q_PROPERTY(int thumbRadius MEMBER radius_ NOTIFY thumbRadiusChanged)
public:
    using QListWidget::QListWidget;
    int thumbRadius() const { return radius_; }
signals:
    void thumbRadiusChanged();
private:
    int radius_ = 7;
};

// The key list: "Mod+Shift+T" in the first column is drawn as key caps (colours from the stylesheet).
class KeyList : public QTreeWidget {
    Q_OBJECT
    Q_PROPERTY(QColor capColor MEMBER cap_)
    Q_PROPERTY(QColor capText MEMBER capText_)
    Q_PROPERTY(int capRadius MEMBER capRadius_)
public:
    explicit KeyList(QWidget *parent = nullptr);
    QColor cap_ {"#1affffff"}, capText_ {Qt::white};
    int capRadius_ = 7;
};

// [-] value [+]  (a spin box without Qt's tiny arrows)
class Stepper : public QWidget {
    Q_OBJECT
public:
    Stepper(double min, double max, double step, int decimals, const QString &suffix, QWidget *parent = nullptr);
    QDoubleSpinBox *box() const { return box_; }
    void setValueQuiet(double v);
signals:
    void valueChanged(double v);
private:
    QDoubleSpinBox *box_;
};

// A slider with its value shown as a percentage next to it.
class PercentSlider : public QWidget {
    Q_OBJECT
public:
    PercentSlider(int min, int max, QWidget *parent = nullptr);
    void setValueQuiet(int v);
    int value() const { return slider_->value(); }
signals:
    void valueChanged(int v);
private:
    QSlider *slider_;
    QLabel *label_;
};

// A rounded group of rows separated by hairlines.
class Card : public QFrame {
public:
    explicit Card(QWidget *parent = nullptr);
    QWidget *addRow(const QString &title, const QString &sub, QWidget *control, QWidget *extra = nullptr);
    void addWidget(QWidget *w);
private:
    QVBoxLayout *lay_;
    int items_ = 0;
};

// A scrolling page with a title.
class Page : public QScrollArea {
public:
    explicit Page(const QString &title, QWidget *parent = nullptr);
    QVBoxLayout *body;
    QLabel *section(const QString &title);
    Card *card();
};

// Runs ~/.local/bin/theme one command at a time and keeps the last `theme json`.
class Theme : public QObject {
    Q_OBJECT
public:
    static Theme *get();
    QJsonObject data;
    void run(const QStringList &args);         // queued; `theme json` is re-read when the queue empties
    void refresh() { run({}); }
    bool busy() const { return proc_ != nullptr; }
signals:
    void changed();                            // data was re-read
    void busyChanged(bool busy);
    void failed(const QString &message);
private:
    QList<QStringList> queue_;
    QProcess *proc_ = nullptr;
    bool dirty_ = false;
    void next();
};

// Calls fn whenever the watched widget gets an event of this type (resize, palette change, ...).
class OnEvent : public QObject {
public:
    OnEvent(QWidget *w, QEvent::Type type, std::function<void()> fn) : QObject(w), type_(type), fn_(std::move(fn))
    {
        w->installEventFilter(this);
    }
protected:
    bool eventFilter(QObject *, QEvent *e) override
    {
        if (e->type() == type_)
            fn_();
        return false;
    }
private:
    QEvent::Type type_;
    std::function<void()> fn_;
};

QWidget *makeAppearancePage();
QWidget *makePowerPage();
QWidget *makeTuningPage();
QWidget *makeMiscPage();
