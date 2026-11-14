# Projekt gry

## Koncepcja

Zrecznosciowa gra o zarzadzaniu ruchem kolejowym na jednej planszy. Inspiracja jest styl rozgrywki Rybulbol (github.com/rybulbol): "dopamine hell", narastajacy chaos i szybkie decyzje.

Gracz steruje zwrotnicami, a nie pojazdami. Musi utrzymac swoj wagonik wewnatrz stacji i zapobiec wszystkim zderzeniom przez **67 sekund**.

## Plansza

Referencja ukladu torow: [Mapa.jpg](Mapa.jpg). Szkic okresla uklad planszy; nie jest gotowym assetem do gry.

Plansza zawiera 6 ciaglych, poziomych, rownoleglych torow biegnacych od lewej do prawej oraz 2 dodatkowe dojazdy, lacznie 8 torow:

- 2 glowne tory posrodku.
- 4 tory boczne: 2 nad torami glownymi i 2 pod nimi, kazdy z odbijakami na lewym i prawym koncu (lacznie 8 odbijakow).
- 2 tory dojazdowe: gorny prawy i dolny lewy. Lacza sie ze skrajnymi torami bocznymi pod katem okolo 30 stopni do poziomu, nie prostopadle. Gorny lewy i dolny prawy dojazd sa usuniete wraz z ich zwrotnicami; w tych miejscach pozostaje ciagly, prosty tor.

Ukosne przejscia lacza rownolegle tory w jedna siec i pozwalaja kierowac wagonik po trasie przypominajacej petle. Dwie grupy lacznikow maja przeciwne skosy: `\` i `/`, zamiast byc rownolegle. Tory boczne nie sa krotkimi odnogami ani dwoma osobnymi obwodami. Kazdy lacznik ma jedna sterowana zwrotnice i jeden bierny koniec, na ktorym pojazd automatycznie dolacza do toru.

Zielone oznaczenia na szkicu to odbijaki na koncach torow bocznych. Lewe i prawe konce torow glownych oraz otwarte konce torow dojazdowych prowadza poza stacje.

Wyjazdy na koncach torow glownych pozostaja otwarte. Usuniecie dwoch dojazdow eliminuje przeciwlegle ukosne wyjazdy na tym samym skrajnym torze, ale nie zabrania przejazdu na wprost torem glownym.

## Sterowanie i zwrotnice

- Gracz klika zwrotnice mysza, aby zmienic ich ustawienie.
- Lacznie jest 12 klikalnych zwrotnic: po jednej na kazdy z dziesieciu lacznikow oraz dwie przy pozostalych dojazdach. Dziesiec biernych wlaczen nie ma ustawien ani obszarow klikniecia.
- Na biernym wlaczeniu pojazd z odnogi dolacza do toru, a pojazd jadacy torem kontynuuje jazde prosto. Nie mozna wybrac odnogi jako zjazdu od biernej strony.
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

Prototyp obejmuje pelna 67-sekundowa runde: wagonik, zwrotnice, odbijaki, pociagi z zapowiedziami wjazdu i kolizjami, licznik pozostalego czasu, ekrany przegranej i wygranej, restart i powrot do menu. Czas rundy i horyzont skalowania spawnu pochodza z `config/traffic.json`.

Scena `scene/game.tscn` jest dostepna przez Start w istniejacym menu. Uklad znajduje sie w `config/cart_prototype.json`: szesc poziomych, rownoleglych torow biegnie od lewej do prawej przez szerokosc planszy. Dwa srodkowe maja otwarte konce, pozostale cztery maja po dwa odbijaki. Dwa krotkie dojazdy lacza sie ze skrajnymi torami bocznymi pod katem 30 stopni do poziomu: gorny prawy i dolny lewy. Razem z koncami torow glownych daje to szesc otwartych wyjazdow. Sekcja `switches` okresla 12 sterowanych zwrotnic, a `merges` dziesiec biernych wlaczen.

Kazda sasiednia para rownoleglych torow ma dwa ukosne przejscia o przeciwnych skosach. W grupie `\` sterowany jest gorny koniec, a dolny jest bierny; w grupie `/` sterowany jest dolny koniec, a gorny jest bierny. Uklad pozwala przemieszczac sie w dol i w gore przez wszystkie szesc torow bez zawracania na polaczeniach. Powrotne obiegi wykorzystuja odbijaki. Szczegolowe rozmieszczenie przejsc pozostaje robocze i jest oznaczone na ekranie jako prowizoryczne; nie jest to dokladna rekonstrukcja kazdej kreski szkicu. Potwierdzona struktura szesciu poziomych, rownoleglych torow, dwoch ukosnych dojazdow i osmiu odbijakow nie jest prowizoryczna.

W prototypie zwrotnica ma trzy dojscia: wspolne, proste i odgalezienie. Ustawienie wybiera wyjazd ze wspolnego dojscia. Wjazd z kazdego z pozostalych dojsc prowadzi na wspolne, bez zawracania. Blokada trwa od dotarcia przodu wagonika do zwrotnicy do opuszczenia jej przez tyl. Dotarcie przodu wagonika do otwartego konca oznacza przegrana.

Bierne wlaczenie ma te same trzy dojscia, ale stala trase: wspolne prowadzi na proste, proste na wspolne, a odgalezienie na wspolne. Nie przechowuje stanu zwrotnicy ani blokady przelaczania. Ruch, kolizje i prognoza spawnu korzystaja z tych samych stalych tras.

### Pociagi i interfejs prototypu

- `ciufa.png` jest grafika wagonika gracza. Pociagi pozostaja tymczasowymi prostokatami Godota o innym kolorze; nie wykorzystuja tej grafiki.
- HUD oraz ekrany przegranej i wygranej sa rzeczywistymi wezlami sceny `config/game_ui.tscn`, instancjonowanymi w `scene/game.tscn`. Mozna edytowac je w Godocie; kod nie tworzy etykiet ani przyciskow w trakcie gry. Motyw jest w `config/game_ui.tres`, wyglad ostrzezen i pojazdow w `config/game_ui.json`.
- Ekran przegranej pokazuje powod: wyjazd wagonika, kolizja wagonika z pociagiem albo kolizja dwoch pociagow. Nakladka blokuje klikniecia planszy, zatrzymana symulacja nie porusza pojazdow ani nie spawnuje kolejnych. Przyciski Retry i Menu korzystaja z istniejacej grafiki przyciskow. Give Up pozostaje dostepny podczas rozgrywki.
- Kazdy z szesciu otwartych koncow jest potencjalnym wjazdem pociagu. Przed pokazaniem zapowiedzi sprawdzana jest prognoza istniejacego ruchu przez czas ostrzezenia, a nastepnie dodatkowe 2 sekundy ruchu z nowym pociagiem. Losowanie obejmuje tylko bezpieczne wejscia. Trasa, ktora przy aktualnych zwrotnicach dociera na obecny tor wagonika w ciagu 10 sekund jazdy pociagu, ma wage 2 zamiast 1. Wybrane wejscie jest oznaczane zoltym pierscieniem. Jezeli zadne wejscie nie jest bezpieczne, zapowiedz jest opozniana bez wymuszania spawnu.
- Prognoza korzysta z tych samych zasad ruchu i wykrywania kolizji co gra, z aktualnym, niezmiennym ustawieniem zwrotnic. Uwzglednia odbijaki, przejazdy przez zwrotnice, obroty obrysow, wyjazdy i wagonik gracza. Nie zmienia rzeczywistych pozycji, blokad, czasu, ustawien zwrotnic ani stanu losowania. Nie symuluje kolejnych spawnow i nie sprawdza zdarzen po zakonczeniu rundy.
- Przez pierwsze 35 sekund aktywna jest najwyzej jedna zapowiedz; od 35. sekundy dopuszczalne sa dwie na roznych wejsciach. Kazda ma wlasny termin wjazdu i ponownych kontroli. Przed faktycznym spawnem ponownie sprawdzany jest wolny obrys oraz prognoza bezpieczenstwa obejmujaca rowniez inne zapowiedziane pociagi. Gdy warunki sie pogorsza, pociag czeka przy tym samym wejsciu z widocznym ostrzezeniem; nie losujemy mu innego wjazdu. Zablokowana zapowiedz nie blokuje drugiego miejsca. Odstep do uzupelnienia wolnych miejsc jest odmierzany od udanego spawnu.
- Ochrona spawnu nie gwarantuje bezpieczenstwa poza krotkim horyzontem ani po pozniejszych zmianach zwrotnic przez gracza. Takie kolizje nadal oznaczaja przegrana. Zwiekszona czestotliwosc nigdy nie omija sprawdzania bezpieczenstwa.
- Parametry pociagow i spawnu pochodza z `config/traffic.json`. Poczatkowe wartosci sa robocze, do balansu: pierwsze ostrzezenie po 2 sekundach, zapowiedz co najmniej 1,8 sekundy, odstep miedzy planowanymi wjazdami dwoch zapowiedzi co najmniej 1,2 sekundy, ochrona po spawnie 2 sekundy, ponowne sprawdzanie odlozonego spawnu co 0,1 sekundy symulacji. Odstep miedzy spawnem i kolejna zapowiedzia maleje liniowo od 4 do 1,8 sekundy w ciagu 67 sekund. Predkosc pociagow pozostaje stala.
- Wszystkie pojazdy korzystaja z jednego ustawienia zwrotnic. Zajecie zwrotnicy przez dowolny pojazd blokuje jej przelaczenie; wyjazd jednego pojazdu nie zwalnia blokady utrzymywanej przez inny.
- Pociag znika dopiero po opuszczeniu otwartego konca przez caly jego obrys. Wyjazd pociagu nie oznacza przegranej.
- Na potrzeby prototypu pojazd ma sztywny prostokatny obrys, obracany przy przejsciu na nowy odcinek; nie jest jeszcze lancuchem osobnych wagonow. Zetkniecie obrysow jest kolizja. Ruch pojazdow jest zsynchronizowany, a wykrywanie kolizji sprawdza cala droge miedzy zdarzeniami, nie tylko pozycje na koncu klatki.
- Po przetrwaniu 67 sekund ekran wygranej zatrzymuje ruch, spawn i zapowiedzi oraz blokuje sterowanie plansza. Pokazuje komunikat i przyciski Retry oraz Menu, tak jak ekran przegranej. Licznik pokazuje pozostaly czas, zaokraglony w gore do pelnej sekundy, i zatrzymuje sie na zerze przy wygranej.
- Symulacja nie wykonuje zdarzen pozniejszych niz koniec rundy. Kolizja, obrot pojazdu powodujacy kolizje lub wyjazd wagonika dokladnie na granicy 67 sekund oznacza przegrana, nie wygrana. Nowy spawn ani zapowiedz nie rozpoczyna sie w chwili konca rundy.
- Restart po obu wynikach zeruje czas, pociagi, zapowiedz, harmonogram spawnu i jego ponownych kontroli, powod przegranej i stan wygranej oraz odtwarza ustawienia zwrotnic, losuje start wagonika i ukrywa obie nakladki.

## Otwarte decyzje

Ponizsze szczegoly nie sa jeszcze uzgodnionymi zasadami i wymagaja ustalenia przed implementacja danej mechaniki:

- Jednoznaczna lista polaczen na podstawie czytelniejszego schematu: identyfikatory zwrotnic, ich mozliwe trasy i zachowanie przy wjezdzie z kazdej strony. Obecny szkic ma 100 x 100 pikseli i nie rozstrzyga tych szczegolow.
- Konkretny zestaw bezpiecznych pozycji startowych, kierunkow i poczatkowych ustawien zwrotnic, po ustaleniu polaczen planszy.
- Wartosci predkosci, odstepow spawnu, czasu ostrzezenia i ksztalt krzywej trudnosci.

## Kryteria weryfikacji MVP

- Wagonik startuje na torze bocznym, jedzie sam i reaguje na zwrotnice.
- Ta sama zwrotnica kieruje ruchem wagonika oraz pociagow.
- Nie mozna przelaczyc zwrotnicy zajetej przez przejezdzajacy pojazd.
- Kazda zwrotnica jest sprawdzana w obu ustawieniach z kazdego z trzech dojsc: rzeczywisty przejazd zachowuje kierunek jazdy w poziomie, a kierunki ruchu przed i po przejsciu tworza kat mniejszy niz 90 stopni. Nie wystarczy sprawdzic samych identyfikatorow polaczen.
- Kazde z dziesieciu biernych wlaczen jest sprawdzane z wszystkich trzech dojsc. Nie da sie go przelaczyc ani zmienic przez klikniecie; z toru nie mozna wjechac na odnoge. Kazdy z dziesieciu lacznikow ma dokladnie jeden sterowany i jeden bierny koniec, a dwie grupy maja przeciwne skosy.
- Odbijaki zawracaja kazdy typ pojazdu.
- Kazdy z czterech bocznych torow ma odbijaki na obu koncach, lacznie osiem. Szesc poziomych, rownoleglych torow jest ciaglych od lewej do prawej i polaczonych w jedna siec przez zwrotnice.
- Dwa pozostale dojazdy, gorny prawy i dolny lewy, maja kat okolo 30 stopni do poziomu. Z kazdego dojazdu mozna dotrzec do drugiego dojazdu oraz prawych wyjazdow obu torow glownych; z kazdego startu mozna dotrzec do wszystkich czterech torow bocznych. Takie trasy moga korzystac z odbijakow, ale nie z zawracania na polaczeniach.
- Jednostronne zjazdy nie zapewniaja trasy z kazdego wejscia do kazdego wyjscia. W obecnym ukladzie z ukosnych dojazdow nie mozna osiagnac lewych wyjazdow torow glownych, bo bierne konce nie pozwalaja wybrac powrotnego zjazdu. Lewe wyjazdy pozostaja otwarte dla pociagow jadacych na wprost z prawych koncow tych torow.
- Usuniete dojazdy i ich zwrotnice nie sa rysowane, klikalne ani dostepne dla spawnu i prognozy. W ich dawnych miejscach mozna przejechac prosto w obu kierunkach.
- Pociagi pojawiaja sie na obu typach wejsc: glownych i dojazdowych.
- Pojawienie sie pociagu jest poprzedzone ostrzezeniem, a zajete miejsce spawnu opoznia wjazd bez tworzenia kolizji.
- Zapowiedz pojawia sie tylko po bezpiecznej prognozie przez jej czas i 2 sekundy po spawnie. Pogorszenie sytuacji podczas ostrzezenia wstrzymuje spawn przy tym samym wejsciu. Brak bezpiecznych wejsc nie wymusza pociagu. Prognoza jest izolowana od stanu gry, a wyniki nie zaleza od dlugosci klatki.
- Pociag moze opuscic kazdy otwarty koniec bez przegranej; wyjazd wagonika dowolnym z nich oznacza przegrana.
- Zarowno zderzenie wagonika z pociagiem, jak i dwoch pociagow natychmiast konczy runde.
- Czestotliwosc spawnu rosnie z czasem, bez wzrostu predkosci pojazdow.
- Przetrwanie 67 sekund konczy runde wygrana.
- Kolizja lub wyjazd wagonika dokladnie w chwili 67 sekund konczy runde przegrana.
- Po zakonczeniu rundy mozna rozpoczac nowa z odnowionym licznikiem i stanem planszy.
