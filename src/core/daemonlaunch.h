// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QFileInfo>

enum class DaemonLaunch
{
    Unavailable,
    Started,
    Failed
};

inline DaemonLaunch launchCaptureInDaemon()
{
    const auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !bus.interface()) {
        return DaemonLaunch::Unavailable;
    }
    const auto owner = bus.interface()->serviceOwner("org.flameshot.Flameshot");
    if (!owner.isValid()) {
        return DaemonLaunch::Unavailable;
    }
    const auto pid = bus.interface()->servicePid(owner.value());
    // Never dispatch a private/local build's capture to an older system binary.
    if (!pid.isValid() ||
        QFileInfo(QStringLiteral("/proc/%1/exe").arg(pid.value()))
            .symLinkTarget() !=
          QFileInfo(QCoreApplication::applicationFilePath())
            .canonicalFilePath()) {
        return DaemonLaunch::Unavailable;
    }
    auto request = QDBusMessage::createMethodCall(
      owner.value(), "/", "org.flameshot.Flameshot", "startCapture");
    request.setAutoStartService(false);
    const auto reply = bus.call(request, QDBus::Block, 1000);
    if (reply.type() == QDBusMessage::ReplyMessage &&
        reply.arguments().size() == 1 && reply.arguments().first().toBool()) {
        return DaemonLaunch::Started;
    }
    if (reply.errorName() == "org.freedesktop.DBus.Error.UnknownMethod" ||
        reply.errorName() == "org.freedesktop.DBus.Error.ServiceUnknown" ||
        reply.errorName() == "org.freedesktop.DBus.Error.NameHasNoOwner") {
        return DaemonLaunch::Unavailable;
    }
    // A timeout may mean the request was already accepted. Do not start a
    // second capture locally when its delivery is uncertain.
    return DaemonLaunch::Failed;
}
