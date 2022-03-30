// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "../OctaNFTFactory.sol";
// import "./mockNFT.sol";
// contract MockOctaFactory is OctaNFTFactory {
//     function createNFTContract(string memory _name, string memory _symbol)
//         external
//         override
//         payable
//         returns (address)
//     {
//         require(msg.value >= platformFee, "Insufficient funds.");
//         (bool success, ) = feeRecipient.call{value: msg.value}("");
//         require(success, "Transfer failed");

//         OctaNFT nft = new MockNFT(
//             _name,
//             _symbol
//         );
//         exists[address(nft)] = true;
//         nftContracts.push(address(nft));
//         nft.transferOwnership(_msgSender());
//         emit ContractCreated(_msgSender(), address(nft));
//         return address(nft);
//     }
// }
