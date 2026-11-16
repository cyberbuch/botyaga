# botyaga — интерфейс

Next.js на порт **3021**. Документацията на проекта е в
[`../README.md`](../README.md) и [`../PLAN.md`](../PLAN.md).

```bash
npm install
npm run dev
```

Отвори http://127.0.0.1:3021. Вход: `superadmin` с паролата, зададена през
`BOTYAGA_SUPERADMIN_PASSWORD` преди първия старт; без env се генерира еднократна
парола в лога (`docker logs botyaga-backend`).

Браузърът говори само с този порт. Next препраща `/v1`, `/health` и `/ready`
към API-то на `127.0.0.1:8093` (`BOTYAGA_API_PROXY`, ако е зададена; в контейнерния
стек — `http://backend:8093`).