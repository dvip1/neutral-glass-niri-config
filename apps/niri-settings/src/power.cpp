// Power & idle: ~/.config/power/power.conf (read by the `idle` daemon, which reloads it within 5 s).
#include "common.h"

namespace {

// key = value   # comment   lines; set() keeps the comment where it was.
struct Conf {
    QString file = home(".config/power/power.conf");
    QStringList lines;

    void load()
    {
        QFile f(file);
        lines = f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).split('\n') : QStringList();
    }
    int find(const QString &key) const
    {
        const QRegularExpression re("^\\s*" + QRegularExpression::escape(key) + "\\s*=");
        for (int i = 0; i < lines.size(); ++i)
            if (re.match(lines[i]).hasMatch())
                return i;
        return -1;
    }
    QString get(const QString &key) const
    {
        const int i = find(key);
        if (i < 0)
            return {};
        QString v = lines[i].section('=', 1);
        return v.section('#', 0, 0).trimmed();
    }
    void set(const QString &key, const QString &value)
    {
        const int i = find(key);
        if (i < 0) {
            lines.insert(lines.size() && lines.last().isEmpty() ? lines.size() - 1 : lines.size(),
                         key + " = " + value);
            return;
        }
        QString &l = lines[i];
        int vs = l.indexOf('=') + 1;
        if (vs < l.size() && l[vs] == ' ')
            ++vs;
        const int hash = l.indexOf('#', vs);
        if (hash < 0)
            l = l.left(vs) + value;
        else
            l = l.left(vs) + value.leftJustified(qMax(hash - vs, int(value.size()) + 1)) + l.mid(hash);
    }
    bool save() const
    {
        QSaveFile f(file);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(lines.join('\n').toUtf8());
        return f.commit();
    }
};

const QList<QPair<QString, QString>> kProfiles = {
    {"Leave as it is", ""}, {"Power saver", "power-saver"}, {"Balanced", "balanced"}, {"Performance", "performance"}};

} // namespace

QWidget *makePowerPage()
{
    auto *page = new Page("Power & Idle");
    auto conf = std::make_shared<Conf>();
    conf->load();

    auto *saveTimer = new QTimer(page);
    saveTimer->setSingleShot(true);
    saveTimer->setInterval(400);
    QObject::connect(saveTimer, &QTimer::timeout, page, [conf] { conf->save(); });

    auto minutes = [&](Card *card, const QString &title, const QString &key) {
        auto *s = new Stepper(0, 600, 1, 0, " min");
        s->box()->setSpecialValueText("Never");
        s->setValueQuiet(conf->get(key).toDouble());
        card->addRow(title, QString(), s);
        QObject::connect(s, &Stepper::valueChanged, page, [=](double v) {
            conf->set(key, QString::number(int(v)));
            saveTimer->start();
        });
    };
    auto profile = [&](Card *card, const QString &title, const QString &key) {
        auto *c = new QComboBox;
        roundPopup(c);
        c->setMinimumWidth(170);
        for (const auto &[label, value] : kProfiles)
            c->addItem(label, value);
        c->setCurrentIndex(qMax(0, c->findData(conf->get(key))));
        card->addRow(title, QString(), c);
        QObject::connect(c, &QComboBox::currentIndexChanged, page, [=](int) {
            conf->set(key, c->currentData().toString());
            saveTimer->start();
        });
    };

    for (const auto &[src, title] : QList<QPair<QString, QString>> {{"battery", "On battery"}, {"ac", "Plugged in"}}) {
        page->section(title);
        auto *card = page->card();
        minutes(card, "Lock the screen after", src + "_lock");
        minutes(card, "Turn the screen off after", src + "_screen_off");
        minutes(card, "Suspend after", src + "_suspend");
        profile(card, src == "ac" ? "Power mode when plugged in" : "Power mode when unplugged", src + "_profile");
    }

    page->section("Battery warnings");
    auto *warn = page->card();
    for (const auto &[key, title, sub] : QList<std::tuple<QString, QString, QString>> {
             {"low_battery", "Low battery", "A normal notification"},
             {"critical_battery", "Critical battery", "Stays until dismissed"}}) {
        auto *s = new Stepper(1, 60, 1, 0, " %");
        s->setValueQuiet(conf->get(key).toDouble());
        warn->addRow(title, sub, s);
        QObject::connect(s, &Stepper::valueChanged, page, [=](double v) {
            conf->set(key, QString::number(int(v)));
            saveTimer->start();
        });
    }

    auto *note = new QLabel("Saved to ~/.config/power/power.conf; the idle daemon applies it within a few seconds.");
    note->setObjectName("rowSub");
    note->setWordWrap(true);
    page->body->addWidget(note);
    page->body->addStretch(1);
    return page;
}
