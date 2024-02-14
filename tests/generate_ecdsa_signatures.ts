// This script is used for creating ECDSA signatures for testing.
//
// Use like this: `npx ts-node ./tests/generate_ecdsa_signatures.ts -n 5 -m "message to sign" -p`
// -n : number of signatures to generate (max 128)
// -m : message to sign
// -p : print signatures
//
// A json file will be written with the signature data.

import { sign, Point, CURVE } from '@noble/secp256k1';
import path = require('path');
import { Signature, SignaturesFileStruct } from "../scripts/input_prep_for_layer_one";
import { jsonReplacer } from "../scripts/json_serde";

const { sha256 } = require('@noble/hashes/sha256');
const fs = require('fs');
const parseArgs = require('minimist');

interface KeyPair {
    pvt: bigint,
    pub: Point,
}

function generate_pvt_pub_key_pairs(n: number): KeyPair[] {
    var pvtkeys: Array<bigint> = [
        66938844460645107025781008991556355714625654511665288941412380224408210845354n,
        11103745739792365897258682640621486163995830732847673942264532053458061009278n,
        18219028028841839326939261514872219893409869517136682756334123738680544985957n,
        44366292562485909035867438023712612905259359219048438210004146835587095814625n,
        72583949399839547415724822536759765593587287244612762500240736634897215125578n,
        90475827897230125173665873539322683723417677540695288238062320714055700263083n,
        79862641006362624980492797181409217540724534636402693613531959830408080293034n,
        32308339495913315402882096963083201007074549438128414631252163147594633694414n,
        59696453565019947873506518730516090944578495403770914153718770209425726406074n,
        95373574739080080935654502474617827325119542291053540882240679732179223937821n,
        61054283497334346697245043455196565253079267524936371063427618247152462373381n,
        43296047848820084882013770361986374962994254485035348736329594358208352822052n,
        23646123578823245789224736034689583040077814644951961293960559783602810911883n,
        28401943004544951289772155222957788471580034397904378371422620481156682319399n,
        28408181956616280257930221947670995199418640305551289796867122604884426202540n,
        47007403823244047475840077040932360744069004869982275409481866771482359347055n,
        45515605509098248788395848254995032664355248962978493528277584702581058308053n,
        73568739845505601564204943101791280067914421758128933215437542883718881054569n,
        11314615397983995308049330264412475517542200996517701327475883357613917216048n,
        89108628201484289381236232173016206169671981061505582143516004105410774436219n,
        32694402690359248735554131798935641397898653618665060179685493955682100688410n,
        36314858834254886897633817618296630737775643888573890447458100021970003628083n,
        52531269538101858895637945445903683813717937470849752480941709616953966954441n,
        95047043497252198596484756872156872028044351719710717850261899678607723160427n,
        81083560390128410377891409031045943439563578755622305224984921024661158433793n,
        55362392588624709982480279310431947185092350594577251443071458804693912749952n,
        82976237275092180705808818854636454468917696458118203729172570610069644935585n,
        68093196809097392336259122828218279960016134848064876682622935813078273036379n,
        98710918697419843744017212063210658046599520849062707809693024802932978393294n,
        10028215561268648534131120379664173011065179896510395903672752604926120781595n,
        63824371924267268164392884119192446905441852005054125912163136883996951819974n,
        87562528875425887511689014572421707807529035966784705562587659882492783987812n,
        81354284700183591263463891920927650536539285667352388900905429610259963794411n,
        15850368000039396340522998329497941819690615853092905846713990310293922646312n,
        53984014830720877411395462439059512051188796910052789567381076993420817860113n,
        49603067912255290583675066928167761473790476803629978008814969432440868504123n,
        18696263453064661932954057536377927259057432799521615289111562142976666775073n,
        32277361627844894223554028002696550445060677345670669772794935022177721640741n,
        58904303127368809592620120964348741113046636274200281280308477624568036717025n,
        67521315698084514840291773674607053763686059928232419138091372418136533263680n,
        13944311637449213000080627458357740259983832991424958922753663847098625683127n,
        66926433565910519831549917155727419718538810809551557194236653240478844040222n,
        23050419870012986012473151821912127274423371474630006667753258413944701399519n,
        91198281598497669935255467308925114256406884015674554101217312404967627207953n,
        68525703439411920399265960530891492368818513218624878402468393694437621844007n,
        43532007721557165962354026861631411702177806635511077444720078397257960488277n,
        67984377895430118683478082511840458372948406018147607835270354448400259397108n,
        40029209000436738499547517731241442380639628177593417169271679995012619726436n,
        89382023834102263089862357259608258719567440165439054599284559983775975933292n,
        56868401343026277900634398816797899776555043772511509035071603312874863885589n,
        42549187222938861298116607554517360292576419964244846003818142973323873453557n,
        91515335349724511911667301953544457860071831073223951295095112713998067449497n,
        46778132852221305974592316569172148076170628496676022819921546493260520139821n,
        64202051965669133027140531030883825001996213168923498362975037851659575582101n,
        13269959280368761792235050553812317376440482357044896570413177491746831291083n,
        12507839792111655048992606331429650715797200496931881029239531842901280337622n,
        65193203161654475193890081362566302823794790147665296710441801509419970243173n,
        47814930245205153526431573348688011950763854538802720031787966509735370158689n,
        76253258915987910177381405965626837094379812265059316609319337606606055610029n,
        10626201015114197336859875766223634345144356107562306325762511114571228422963n,
        61605263490387904626881723064209091867966943210339271886004426825961199896451n,
        38550654437855997136959903531801192213513637665483610136387315188791807848476n,
        48330285813791767618691938513711721047946063653459152026595774590548503634907n,
        59194623341472148865771405109144504111655113592017353727865340457472121370116n,
        86909987478739278916293987740925291592051294640413250856067718372158564842215n,
        89735349125490173724710994111397406706022442143669028772227978852783227206922n,
        94727673581212922170210977975899058466418283052006398336329191290829190325920n,
        58130131444074154655523437318300209851247089629948923719749782971195789968727n,
        66761151414862709990070536510991546062850371268714838415397558922158970064256n,
        60435222539564732343317456916736911665165299055396362178585888437315324959878n,
        45334702447583295672482377788408971761439508071917474930865660320110230706962n,
        76818356376373222451028133944506308415619716249304086640860907771072844433479n,
        69735415239967723805232448993828544038754292471732172002806360889949152748861n,
        17069694361201860770052240967792378442229110804347455473414770741429695920929n,
        40556761990092583398939967867106652917402064282664569450842923095127771030021n,
        14480034568157144909481281626375036712698950302634569151152715490013873006349n,
        88121947882496953708619708383665883910537003582170807530258872796376314820644n,
        70553831074256951419741043375135292271306144967134161798627585361601947051233n,
        51084382809073386294466545441140055376998258546192525225755111297708912911964n,
        90945193824867099593193523661711638023771084822134796987102273412356019774587n,
        98185356854852388163067422939568970671220483952515856115945863395282184042344n,
        94146812987214115314891263152731024114710556135224440580781289179322125351785n,
        43728809628275244494593978667527423913059616026090571496890775874460259429423n,
        95147351923415715950021643416400895878287709489475237079570332414155333532041n,
        27993944347197829017398806364649710854299599621636215377914809594674242791149n,
        84531079513966380360799724751429384822335055936214960293413578076972067526028n,
        94578556071725364583547435055470556886892022449474005207458285376484157980548n,
        36157835464408507812088372335709459306539097450318764097109853693896831455524n,
        34621254560188994917716871035821587512947197304532603567772341865131579837566n,
        53188915174273868590565716260991513221611985369584245857811021806711351157773n,
        72869596642545159934471161571421833298814046612900770232314503624365688128543n,
        36927364704392196047196905956462984821722062822155404909111123980617536454170n,
        31628223113111669638210734964976229910647219670719966905372750223068014549723n,
        27793396263363108203810448822208078240276641283495309238419346231398980606947n,
        90863319292607921614679039519514353806855667729009924902157392688225484311999n,
        28379546522424614668570792280042551019389046328892955591929437614438848114448n,
        34706106261054268108879126277046174121827963946572965134477686641391757773173n,
        56513798926731637338542431542887272550492226060757328096523723663566175444449n,
        59205212441098301434573682143235880606934075707817106958986780747031127371915n,
        34067393333657269613525948693643279727629684510812935362567610267680301038616n,
        24215486266258693514339680396566356270648698786169726637050305096225580029846n,
        34134747380519983720059095895044051671534362648563033491804398457763836889095n,
        77550435549996013437381867591961597682142214358251803566942820466122378158785n,
        75636873620275302071499862238875138812359597430987719788191913447988106518056n,
        30588954993831165298071227308356015850538880391949560325812881282563403607308n,
        75741711485299634272254744841706273817490689437903042362305804339201955145608n,
        37427262883160862878621004640455494090401314312821073977113905449667408505109n,
        71555815240880872920034664290810715047893397503498326062596808939603784097319n,
        68597491237669383199765086321282410025432915215296450943355771296170025987930n,
        76423286803574167500031655793598949007575017491156487885820456008118707133035n,
        63777568703401991599374720963878064386967482112595330225972995205057535257388n,
        26025029413846502763060849410911110654121992345519793357415507890758771868362n,
        10989636328779273255530854073867317626371618723680994403828256032292148239415n,
        31087612917457122157869095644324297866814563682830391792591961273080314584241n,
        99507504421333953214839042619230036874400670213855279073418924147000294414212n,
        62435493576111419704213965081049253005340682459637534715070118237578910290708n,
        52355435278116983709531198195086268993747306817342898158736416546333036316630n,
        14714209640578851598042082192525472291939763362779133058210414741922716217748n,
        11740195357676763661226453815191948147657587092909596569393630897676550435622n,
        78926182703516350310546517390669344993931558348690924722045327836200057301291n,
        54425364929047908659122030220660138787432587336022020730421384079578772697029n,
        84644494860552168829975913309866219567049367349381263517269336438656886206248n,
        52047909384434655730347808145333030078944788442741553018940777703524099201495n,
        54611435615224302356370641946496935670765169931539675985816007859948567740859n,
        45070832766322092287936489211249000463610330135113857167369234918293214851714n,
        10340134798722660935916917465760746856077034306772971461491515098744732544843n,
        96982741287019189601032895999562654931930260330998102822134887640606021449200n,
        54506822518630181196369445464085781062051930334543736907392887951602852562600n
    ];

    var pairs: KeyPair[] = [];

    for (var i = 0; i < n; i++) {
        var pubkey: Point = Point.fromPrivateKey(pvtkeys[i]);
        pairs.push({pvt: pvtkeys[i], pub: pubkey});
    }

    return pairs;
}

// bigendian
function bigint_to_Uint8Array(x: bigint) {
    var ret: Uint8Array = new Uint8Array(32);
    for (var idx = 31; idx >= 0; idx--) {
        ret[idx] = Number(x % 256n);
        x = x / 256n;
    }
    return ret;
}

// bigendian
function Uint8Array_to_bigint(x: Uint8Array) {
    var ret: bigint = 0n;
    for (var idx = 0; idx < x.length; idx++) {
        ret = ret * 256n;
        ret = ret + BigInt(x[idx]);
    }
    return ret;
}

// Calculates a modulo b
function mod(a: bigint, b: bigint = CURVE.P): bigint {
    const result = a % b;
    return result >= 0n ? result : b + result;
}

// Inverses number over modulo
function invert(number: bigint, modulo: bigint = CURVE.P): bigint {
    if (number === 0n || modulo <= 0n) {
        throw new Error(`invert: expected positive integers, got n=${number} mod=${modulo}`);
    }

    // Eucledian GCD https://brilliant.org/wiki/extended-euclidean-algorithm/
    let a = mod(number, modulo);
    let b = modulo;
    let x = 0n, y = 1n, u = 1n, v = 0n;

    while (a !== 0n) {
        const q = b / a;
        const r = b % a;
        const m = x - u * q;
        const n = y - v * q;
        b = a, a = r, x = u, y = v, u = m, v = n;
    }
    const gcd = b;
    if (gcd !== 1n) throw new Error('invert: does not exist');

    return mod(x, modulo);
}

// computing v = r_i' in R_i = (r_i, r_i')
function construct_r_prime(r: bigint, s: bigint, pvtkey: bigint, msg_hash: Uint8Array): bigint {
    const { n } = CURVE;

    var msg_hash_bigint: bigint = Uint8Array_to_bigint(msg_hash);

    var p_1 = Point.BASE.multiply(mod(msg_hash_bigint * invert(s, n), n));
    var p_2 = Point.fromPrivateKey(pvtkey).multiply(mod(r * invert(s, n), n));
    var p_res = p_1.add(p_2);

    return p_res.y;
}


async function generate_sigs(msghash: Uint8Array, key_pairs: KeyPair[]): Promise<Signature[]> {
    var sigs: Signature[] = [];

    for (var i = 0; i < key_pairs.length; i++) {
        var pvtkey = key_pairs[i].pvt;
        var pubkey = key_pairs[i].pub;

        var sig: Uint8Array = await sign(msghash, bigint_to_Uint8Array(key_pairs[i].pvt), {
            canonical: true,
            der: false,
        });

        var r: bigint = Uint8Array_to_bigint(sig.slice(0, 32));
        var s: bigint = Uint8Array_to_bigint(sig.slice(32, 64));
        var r_prime: bigint = construct_r_prime(r, s, pvtkey, msg_hash);

        sigs.push({ r, s, r_prime, pubkey });
    }

    return sigs;
}

var argv = parseArgs(process.argv.slice(2), {
    default: { "n": 2, "m": "my message to sign", "p": false }
});
var num_sigs = argv.n;
var msg = argv.m

var msg_hash: Uint8Array = sha256(msg);
var pairs = generate_pvt_pub_key_pairs(argv.n);

generate_sigs(msg_hash, pairs).then(sigs => {
    var output: SignaturesFileStruct = {
        msg_hash,
        signatures: sigs,
    };
    var filename = "signatures_" + num_sigs + ".json";

    const json = JSON.stringify(output, jsonReplacer);

    if (argv.p === true) {
        console.log("Writing the following signature data to", filename, sigs);
    }

    fs.writeFileSync(path.join(__dirname, filename), json);
});

