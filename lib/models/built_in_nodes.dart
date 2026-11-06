// Written by tools/update-nodes from https://nodes.tox.chat/json.
// Run it again before each release.

import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';

/// The nodes bTox starts from.
final builtInBootstrapNodes = BootstrapNodeList(
  nodes: [
    for (final (ipv4, port, tcpPorts, key, statusTcp)
        in const <(String, int, List<int>, String, bool)>[
          (
            '144.217.167.73',
            33445,
            [33445, 3389],
            '7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C',
            true,
          ),
          (
            'tox.abilinski.com',
            33445,
            [],
            '10C00EB250C3233E343E2AEBA07115A5C28920E9C8D29492F6D00B29049EDC7E',
            false,
          ),
          (
            '205.185.115.131',
            53,
            [3389, 443, 33445, 53],
            '3091C6BEB2A993F1C6300C16549FABA67098FF3D62C6D253828B531470B53D68',
            true,
          ),
          (
            'tox1.mf-net.eu',
            33445,
            [3389, 33445],
            'B3E5FA80DC8EBD1149AD2AB35ED8B85BD546DEDE261CA593234C619249419506',
            true,
          ),
          (
            '139.162.110.188',
            33445,
            [3389, 443, 33445],
            'F76A11284547163889DDC89A7738CF271797BF5E5E220643E97AD3C7E7903D55',
            true,
          ),
          (
            'tox2.mf-net.eu',
            33445,
            [3389, 33445],
            '70EA214FDE161E7432530605213F18F7427DC773E276B3E317A07531F548545F',
            true,
          ),
          (
            '172.105.109.31',
            33445,
            [33445],
            'D46E97CF995DC1820B92B7D899E152A217D36ABE22730FEA4B6BF1BFC06C617C',
            true,
          ),
          (
            '144.172.88.203',
            33445,
            [33445],
            '2016A0F2797EE3A8B004BA623F11AAFC8146F1B8F45107232A1A1AECCE856674',
            true,
          ),
          (
            '91.146.66.26',
            33445,
            [],
            'B5E7DAC610DBDE55F359C7F8690B294C8E4FCEC4385DE9525DBFA5523EAD9D53',
            false,
          ),
          (
            '172.104.215.182',
            33445,
            [443, 33445, 3389],
            'DA2BD927E01CD05EBCC2574EBE5BEBB10FF59AE0B2105A7D1E2B40E49BB20239',
            true,
          ),
          (
            'tox.initramfs.io',
            33445,
            [3389, 33445],
            '3F0A45A268367C1BEA652F258C85F4A66DA76BCAA667A49E770BCC4917AB6A25',
            true,
          ),
          (
            'tox3.mf-net.eu',
            33445,
            [33445, 3389],
            'F4FC9398B7167668ED2BCF85634E04D4CDCDD2F95DA5F305BD234888B6E6A771',
            true,
          ),
          (
            '188.214.122.30',
            33445,
            [3389, 33445],
            '2A9F7A620581D5D1B09B004624559211C5ED3D1D712E8066ACDB0896A7335705',
            true,
          ),
          (
            '95.181.230.108',
            33445,
            [3389, 33445],
            'B5FFECB4E4C26409EBB88DB35793E7B39BFA3BA12AC04C096950CB842E3E130A',
            true,
          ),
          (
            'tox4.mf-net.eu',
            33445,
            [33445, 3389],
            'DCD342A0D5E2AA8E35C2BD2C7988F906EEB631B35100170A7F30E77D7F596442',
            true,
          ),
          (
            '188.245.84.166',
            33445,
            [3389, 443, 33445],
            '96B66D300BA2B59B98FC42DB1325E7092388F0379593E680ABDBEA03B9C9CE03',
            true,
          ),
          (
            '86.107.187.54',
            33445,
            [33445, 3389],
            '2C0F90965134C7BEFAFE72B077A19221628D7045BB51C1165A2C75CDB2B32634',
            true,
          ),
          (
            '119.59.101.63',
            33445,
            [33445, 443],
            '197F746696062FA3BD07BB3BC0656ABD6692B4DAA27DACF0F474754F2B09B060',
            true,
          ),
          (
            '172.86.77.39',
            33445,
            [33445],
            'AFFD3FAD3460E62A894E439534B27E5A5DCFE379C1C0FB78DEF1B150A87E900F',
            true,
          ),
          (
            '5.19.249.240',
            38296,
            [38296, 3389],
            'DA98A4C0CD7473A133E115FEA2EBDAEEA2EF4F79FD69325FC070DA4DE4BA3238',
            true,
          ),
          (
            '45.32.184.23',
            33445,
            [],
            '81C916A3605724106C2E7487DC72FF2F9EB662EB34C85C0C692D8312B442635C',
            false,
          ),
          (
            '3.0.24.15',
            33445,
            [],
            'E20ABCF38CDBFFD7D04B29C956B33F7B27A3BB7AF0618101617B036E4AEA402D',
            false,
          ),
          (
            '43.198.227.166',
            33445,
            [],
            'AD13AB0D434BCE6C83FE2649237183964AE3341D0AFB3BE1694B18505E4E135E',
            false,
          ),
          (
            'tox.hidemybits.com',
            443,
            [],
            '5D57B95EE4A7F37BA031DAD0CBD9510A9C96FFE09C1CE24A9C33746F39817D6E',
            false,
          ),
          (
            '167.17.40.142',
            33445,
            [],
            'E84453123B44A47120FFB469CBCDEEF078D3785D7AD7F6C5B2351CB5DDE2C54C',
            false,
          ),
          (
            '145.239.1.105',
            33445,
            [],
            '1658A9A64046C20F48FB2A47E56045233AB0AC0706974FC5904F9E74F452D908',
            false,
          ),
        ])
      BootstrapNode(
        ipv4: ipv4,
        port: port,
        tcpPorts: tcpPorts,
        publicKey: PublicKey.fromJson(key),
        statusTcp: statusTcp,
      ),
  ],
);
