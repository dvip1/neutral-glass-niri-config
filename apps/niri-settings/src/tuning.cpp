// Theme details: per-theme tunables (`theme setkey` / `theme unset` write them into themes/NAME.toml).
#include "common.h"

namespace {

enum Kind { Bool, Percent, Number, Font };

struct Tunable {
    QString key, title, sub;
    Kind kind;
    double min = 0, max = 0, step = 1;
    int decimals = 0;
    QString suffix;
};

const QList<QPair<QString, QList<Tunable>>> kGroups = {
    {"Effects", {
        {"effects.blur", "Blur", "Frosted glass behind the bar, menus and kitty", Bool},
        {"effects.kitty_opacity", "Kitty opacity", {}, Percent, 30, 100},
    }},
    {"Transparency", {
        {"opacity.alpha_bar", "Bar", {}, Percent, 10, 100},
        {"opacity.alpha_panel", "Launcher and menus", {}, Percent, 10, 100},
        {"opacity.alpha_card", "Notification cards", {}, Percent, 10, 100},
        {"opacity.alpha_osd", "Volume / brightness popup", {}, Percent, 10, 100},
    }},
    {"Shape", {
        {"shape.radius", "Corner radius", "Windows, bar, cards", Number, 0, 30, 1, 0, " px"},
        {"shape.radius_large", "Large corner radius", "Launcher, menus, popups", Number, 0, 30, 1, 0, " px"},
        {"shape.radius_pill", "Pill radius", "Pills on the bar, tooltips", Number, 0, 30, 1, 0, " px"},
        {"shape.radius_small", "Small radius", "Buttons, selections inside cards", Number, 0, 20, 1, 0, " px"},
        {"shape.gaps", "Window gaps", {}, Number, 0, 40, 1, 0, " px"},
        {"shape.ring_width", "Focus ring width", {}, Number, 0, 8, 1, 0, " px"},
    }},
    {"Font", {
        {"font.family", "Interface font", {}, Font},
        {"font.size", "Text size", "Notifications, menus, popups", Number, 8, 24, 0.5, 1, " px"},
        {"font.bar_size", "Bar text size", {}, Number, 8, 24, 0.5, 1, " px"},
    }},
    {"Motion", {
        {"motion.hover_in", "Hover in", "How fast things light up under the pointer", Number, 0, 1000, 10, 0, " ms"},
        {"motion.hover_out", "Hover out", {}, Number, 0, 1000, 10, 0, " ms"},
        {"motion.pill_ms", "Panels and pills", "Moving, stretching, opening", Number, 0, 1000, 10, 0, " ms"},
    }},
};

QString fmt(double v)
{
    return QString::number(v, 'g', 6);
}

} // namespace

QWidget *makeTuningPage()
{
    auto *page = new Page("Theme Details");
    auto *T = Theme::get();
    auto *intro = new QLabel;
    intro->setObjectName("rowSub");
    intro->setWordWrap(true);
    page->body->addWidget(intro);

    struct Row {
        Tunable t;
        QWidget *control;
        QToolButton *reset;
        QTimer *timer;
    };
    auto rows = std::make_shared<QList<Row>>();

    for (const auto &[group, items] : kGroups) {
        page->section(group);
        auto *card = page->card();
        for (const Tunable &t : items) {
            auto *reset = new QToolButton;
            reset->setObjectName("reset");
            reset->setText("Reset");
            reset->setToolTip("Use the shared default from theme.toml");
            reset->setCursor(Qt::PointingHandCursor);
            auto *timer = new QTimer(page);
            timer->setSingleShot(true);
            timer->setInterval(t.kind == Bool ? 0 : 600);
            QWidget *control = nullptr;
            std::function<QString()> value;
            switch (t.kind) {
            case Bool: {
                auto *s = new Switch;
                control = s;
                value = [s] { return QString(s->isChecked() ? "true" : "false"); };
                QObject::connect(s, &QAbstractButton::toggled, timer, qOverload<>(&QTimer::start));
                break;
            }
            case Percent: {
                auto *s = new PercentSlider(int(t.min), int(t.max));
                control = s;
                value = [s] { return fmt(s->value() / 100.0); };
                QObject::connect(s, &PercentSlider::valueChanged, timer, qOverload<>(&QTimer::start));
                break;
            }
            case Number: {
                auto *s = new Stepper(t.min, t.max, t.step, t.decimals, t.suffix);
                control = s;
                value = [s] { return fmt(s->box()->value()); };
                QObject::connect(s, &Stepper::valueChanged, timer, qOverload<>(&QTimer::start));
                break;
            }
            case Font: {
                auto *c = new QComboBox;
                c->setEditable(true);
                c->setInsertPolicy(QComboBox::NoInsert);
                c->addItems(QFontDatabase::families());
                c->setMinimumWidth(220);
                c->setMaxVisibleItems(14);
                roundPopup(c);
                control = c;
                value = [c] { return c->currentText().trimmed(); };
                QObject::connect(c, &QComboBox::textActivated, timer, qOverload<>(&QTimer::start));
                break;
            }
            }
            QObject::connect(timer, &QTimer::timeout, page, [T, key = t.key, value] {
                const QString v = value();
                if (!v.isEmpty())
                    T->run({"setkey", key, v});
            });
            QObject::connect(reset, &QToolButton::clicked, page, [T, key = t.key, timer] {
                timer->stop();
                T->run({"unset", key});
            });
            card->addRow(t.title, t.sub, control, reset);
            rows->append({t, control, reset, timer});
        }
    }
    page->body->addStretch(1);

    auto fill = [=] {
        const QString name = T->data["current"].toString();
        intro->setText(QString("Fine-tuning for the <b>%1</b> theme, saved in themes/%1.toml. "
                               "<i>Reset</i> goes back to the shared default.").arg(name));
        const QJsonObject values = T->data["values"].toObject();
        for (const Row &r : *rows) {
            if (r.timer->isActive())            // still being edited: don't fight the user
                continue;
            const QJsonObject o = values[r.t.key].toObject();
            const QJsonValue v = o["value"];
            r.reset->setVisible(o["own"].toBool());
            switch (r.t.kind) {
            case Bool: static_cast<Switch *>(r.control)->setCheckedQuiet(v.toBool()); break;
            case Percent: static_cast<PercentSlider *>(r.control)->setValueQuiet(qRound(v.toDouble() * 100)); break;
            case Number: static_cast<Stepper *>(r.control)->setValueQuiet(v.toDouble()); break;
            case Font: {
                auto *c = static_cast<QComboBox *>(r.control);
                QSignalBlocker b(c);
                c->setCurrentText(v.toString());
                break;
            }
            }
        }
    };
    QObject::connect(T, &Theme::changed, page, fill);
    if (!T->data.isEmpty())
        fill();
    return page;
}
