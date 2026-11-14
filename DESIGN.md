# Projekt gry

## Koncepcja

Zrecznosciowa gra o zarzadzaniu ruchem kolejowym na jednej planszy. Inspiracja jest styl rozgrywki Rybulbol (github.com/rybulbol): "dopamine hell", narastajacy chaos i szybkie decyzje.

Gracz steruje zwrotnicami, a nie pojazdami. Musi utrzymac swoj wagonik wewnatrz stacji i zapobiec wszystkim zderzeniom przez **67 sekund**.

## Plansza

Referencja ukladu torow: [Mapa.jpg](Mapa.jpg). Szkic okresla uklad planszy; nie jest gotowym assetem do gry.

Plansza zawiera 6 ciaglych, poziomych, rownoleglych torow biegnacych od lewej do prawej oraz 4 dodatkowe dojazdy, lacznie 10 torow:

- 2 glowne tory posrodku.
- 4 tory boczne: 2 nad torami glownymi i 2 pod nimi, kazdy z odbijakami na lewym i prawym koncu (lacznie 8 odbijakow).
- 4 tory dojazdowe: gorny lewy, gorny prawy, dolny lewy i dolny prawy. Lacza sie ze skrajnymi torami bocznymi pod katem okolo 30 stopni do poziomu, nie prostopadle.

Ukosne przejscia ze zwrotnicami lacza rownolegle tory w jedna siec i pozwalaja kierowac wagonik po trasie przypominajacej petle. Tory boczne nie sa krotkimi odnogami ani dwoma osobnymi obwodami. Kazde polaczenie torow zaznaczone na szkicu jest przelaczane zwrotnica.

Zielone oznaczenia na szkicu to odbijaki na koncach torow bocznych. Lewe i prawe konce torow glownych oraz otwarte konce torow dojazdowych prowadza poza stacje.

## Sterowanie i zwrotnice

- Gracz klika zwrotnice mysza, aby zmienic ich ustawienie.
- Ustawienie zwrotnicy wplywa na wszystkie przejezdzajace pojazdy: wagonik gracza i pociagi.
- Przelaczenie zwrotnicy jest zablokowane, dopoki przejezdzajacy pojazd jej nie opusci.
- Przejazd przez zwrotnice zachowuje kierunek jazdy w poziomie. Wspolne dojscie musi znajdowac sie po przeciwnej stronie zwrotnicy niz odgalezienie, aby przejazd na inny tor nie powodowal zawracania. Kierunek odwraca tylko odbijak.
- Gracz nie steruje bezposrednio ruchem wagonika i nie moze go zatrzymac ani wyhamowac.

## Wagonik gracza

- Na poczatku rundy wagonik pojawia sie na losowym torze bocznym.
- Start jest losowany sposrod wczesniej sprawdzonych pozycji, wraz z kierunkiem ruchu i poczatkowymi ustawieniami zwrotnic dajacymi graczowi czas na reakcje.
- Wagonik porusza sie automatycznie przez cala aktywna runde.
- Zwrotnice wyznaczaja jego dalsza trase.
- Odbijak odwraca kierunek jego ruchu.
- Wyjazd wagonika poza stacje natychmiast konczy runde przegrana, niezaleznie od wybranego wyjazdu.

## Pociagi

- Pociagi pojawiaja sie na torach glownych i dojazdowych, wjezdzajac na stacje.
- Przed pojawieniem sie pociagu przy odpowiednim wejsciu wyswietlane jest ostrzezenie. Czas ostrzezenia pochodzi z konfiguracji.
- Jezeli miejsce spawnu jest zajete, pojawienie sie pociagu czeka na wolne miejsce, zamiast powodowac natychmiastowa kolizje.
- Poruszaja sie automatycznie i reaguja na te same zwrotnice co wagonik gracza.
- Odbijaki odwracaja kierunek ruchu pociagow, tak samo jak wagonika.
- Pociag moze bezpiecznie opuscic plansze dowolnym otwartym koncem toru, takze torem dojazdowym. Po wyjezdzie jest usuwany z rozgrywki.
- Gracz musi zapobiegac zarowno zderzeniom pociagow z wagonikiem, jak i zderzeniom pociagow miedzy soba.

## Przebieg rundy

1. Wagonik rozpoczyna ruch na losowym torze bocznym i rozpoczyna sie odliczanie.
2. Pociagi wjezdzaja na stacje przez tory glowne i dojazdowe.
3. Gracz przelacza zwrotnice, utrzymujac wagonik na stacji i wyprowadzajac pociagi bez zderzen.
4. Wraz z uplywem czasu pociagi pojawiaja sie coraz czesciej.
5. Runda konczy sie natychmiast po przegranej albo po przetrwaniu 67 sekund.

### Wygrana

Przetrwanie 67 sekund bez zadnego warunku przegranej.

Kolizja lub wyjazd wagonika w czasie do 67 sekund wlacznie oznacza przegrana. Zdarzenie przypadajace dokladnie na koniec odliczania ma pierwszenstwo przed wygrana.

### Przegrana

Kazde z ponizszych zdarzen natychmiast konczy runde:

- Wagonik gracza opuszcza stacje.
- Wagonik gracza zderza sie z pociagiem.
- Dowolne dwa pociagi zderzaja sie ze soba.

## Narastanie trudnosci

Trudnosc rosnie poprzez zwiekszanie czestotliwosci pojawiania sie pociagow. Predkosci pojazdow nie rosna w trakcie rundy.

Dokladna krzywa czestotliwosci spawnu, poczatkowe i koncowe odstepy oraz predkosci pojazdow wymagaja testow rozgrywki. Nie sa jeszcze ustalone.

## Zakres MVP na game jam

- Jedna plansza oparta na `Mapa.jpg`.
- Automatyczny ruch wagonika i pociagow po torach.
- Zwrotnice przelaczane mysza, wspolne dla wszystkich pojazdow.
- Odbijaki odwracajace kierunek ruchu wszystkich pojazdow.
- Losowanie bocznego toru startowego wagonika.
- Spawn pociagow na torach glownych i dojazdowych.
- Coraz czestszy spawn w trakcie rundy.
- Ostrzezenia przy wejsciach i oczekiwanie na zwolnienie zajetego miejsca spawnu.
- Bezpieczne usuwanie pociagow po opuszczeniu planszy.
- Wykrywanie wszystkich zderzen i wyjazdu wagonika.
- Widoczny licznik pozostalego czasu.
- Ekran wygranej lub przegranej z mozliwoscia restartu.

## Konfiguracja i zasoby

- Silnik projektu: Godot.
- Wszystkie parametry do strojenia rozgrywki trafiaja do plikow w `config/`, zamiast do stalych rozsianych po skryptach.
- Konfiguracja obejmuje m.in. czas rundy (67 sekund), predkosci pojazdow, czasy i czestotliwosci spawnu, jego skalowanie oraz czas ostrzezenia przed wjazdem pociagu.
- Parametry wizualne do strojenia, takie jak rozmiary i kolory, rowniez pochodza z `config/`.
- Grafika i dzwiek pochodza od artysty. Nie generujemy assetow za pomoca AI.
- Brakujace zasoby nalezy zglosic, zamiast tworzyc zastepcza grafike lub dzwiek.

### Wyjatek dla prototypu

Za zgoda autora prototyp moze korzystac z natywnych linii, figur i tekstu Godota jako tymczasowej wizualizacji. Nie generujemy plikow graficznych ani audio. Docelowe assety nadal pochodza od artysty.

Pierwszy etap obejmuje tylko wagonik, zwrotnice, odbijaki, przegrana po wyjezdzie, restart i powrot do menu. Nie zawiera jeszcze pociagow ani 67-sekundowej rundy.

Scena `scene/game.tscn` jest dostepna przez Start w istniejacym menu. Uklad znajduje sie w `config/cart_prototype.json`: szesc poziomych, rownoleglych torow biegnie od lewej do prawej przez szerokosc planszy. Dwa srodkowe maja otwarte konce, pozostale cztery maja po dwa odbijaki. Cztery krotkie dojazdy lacza sie ze skrajnymi torami bocznymi pod katem 30 stopni do poziomu: dwa u gory i dwa u dolu, od lewej i od prawej. Razem z koncami torow glownych daje to osiem otwartych wyjazdow.

Kazda sasiednia para rownoleglych torow ma dwa ukosne przejscia. Przejscia sa rozsuniete wzdluz planszy tak, aby mozna bylo przejechac miedzy wszystkimi szescioma torami bez zawracania na zwrotnicach. Powrotne obiegi wykorzystuja odbijaki. Szczegolowe rozmieszczenie przejsc pozostaje robocze i jest oznaczone na ekranie jako prowizoryczne; nie jest to dokladna rekonstrukcja kazdej kreski szkicu. Potwierdzona struktura szesciu poziomych, rownoleglych torow, czterech ukosnych dojazdow i osmiu odbijakow nie jest prowizoryczna.

W prototypie zwrotnica ma trzy dojscia: wspolne, proste i odgalezienie. Ustawienie wybiera wyjazd ze wspolnego dojscia. Wjazd z kazdego z pozostalych dojsc prowadzi na wspolne, bez zawracania. Blokada trwa od dotarcia przodu wagonika do zwrotnicy do opuszczenia jej przez tyl. Dotarcie przodu wagonika do otwartego konca oznacza przegrana.

## Otwarte decyzje

Ponizsze szczegoly nie sa jeszcze uzgodnionymi zasadami i wymagaja ustalenia przed implementacja danej mechaniki:

- Jednoznaczna lista polaczen na podstawie czytelniejszego schematu: identyfikatory zwrotnic, ich mozliwe trasy i zachowanie przy wjezdzie z kazdej strony. Obecny szkic ma 100 x 100 pikseli i nie rozstrzyga tych szczegolow.
- Konkretny zestaw bezpiecznych pozycji startowych, kierunkow i poczatkowych ustawien zwrotnic, po ustaleniu polaczen planszy.
- Sposob wyboru wejsc spawnu pociagow oraz obsluga kolejnych zapowiedzi, gdy poprzedni spawn nadal czeka na wolne miejsce.
- Forma wizualna ostrzezenia o nadjezdzajacym pociagu.
- Wartosci predkosci, odstepow spawnu, czasu ostrzezenia i ksztalt krzywej trudnosci.

## Kryteria weryfikacji MVP

- Wagonik startuje na torze bocznym, jedzie sam i reaguje na zwrotnice.
- Ta sama zwrotnica kieruje ruchem wagonika oraz pociagow.
- Nie mozna przelaczyc zwrotnicy zajetej przez przejezdzajacy pojazd.
- Kazda zwrotnica jest sprawdzana w obu ustawieniach z kazdego z trzech dojsc: rzeczywisty przejazd zachowuje kierunek jazdy w poziomie, a kierunki ruchu przed i po przejsciu tworza kat mniejszy niz 90 stopni. Nie wystarczy sprawdzic samych identyfikatorow polaczen.
- Odbijaki zawracaja kazdy typ pojazdu.
- Kazdy z czterech bocznych torow ma odbijaki na obu koncach, lacznie osiem. Szesc poziomych, rownoleglych torow jest ciaglych od lewej do prawej i polaczonych w jedna siec przez zwrotnice.
- Cztery dojazdy maja kat okolo 30 stopni do poziomu. Z kazdego dojazdu mozna wyznaczyc i przejechac trase do kazdego z pozostalych siedmiu wyjazdow; z kazdego startu mozna dotrzec do wszystkich czterech torow bocznych. Takie trasy moga korzystac z odbijakow, ale nie z zawracania na zwrotnicach.
- Pociagi pojawiaja sie na obu typach wejsc: glownych i dojazdowych.
- Pojawienie sie pociagu jest poprzedzone ostrzezeniem, a zajete miejsce spawnu opoznia wjazd bez tworzenia kolizji.
- Pociag moze opuscic kazdy otwarty koniec bez przegranej; wyjazd wagonika dowolnym z nich oznacza przegrana.
- Zarowno zderzenie wagonika z pociagiem, jak i dwoch pociagow natychmiast konczy runde.
- Czestotliwosc spawnu rosnie z czasem, bez wzrostu predkosci pojazdow.
- Przetrwanie 67 sekund konczy runde wygrana.
- Kolizja lub wyjazd wagonika dokladnie w chwili 67 sekund konczy runde przegrana.
- Po zakonczeniu rundy mozna rozpoczac nowa z odnowionym licznikiem i stanem planszy.
