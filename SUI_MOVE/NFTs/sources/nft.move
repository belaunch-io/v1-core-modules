/// A minimalist example to demonstrate how to create an NFT like object
/// on Sui. The user should be able to use the wallet command line tool
/// (https://docs.sui.io/build/wallet) to mint an NFT. For example,
/// `wallet example-nft --name <Name> --description <Description> --url <URL>`
module belaunch::nft {
    use std::string::{utf8, String};

    use sui::url::{Self, Url};    
    use sui::object::{Self, ID, UID};
    use sui::event;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::package;
    use sui::display;

    // ======= Types =======
    struct NFT has drop {}

    /// An example NFT that can be minted by anybody
    struct BeLaunchNFT has key, store {
        id: UID,
        /// Name for the token
        name: String,
        /// Description of the token
        description: String,
        /// URL for the token
        image_url: Url,
        // TODO: allow custom attributes
    }

    struct MintNFTEvent has copy, drop {
        // The Object ID of the NFT
        object_id: ID,
        // The creator of the NFT
        creator: address,
        // The name of the NFT
        name: String,
    }

    // ======= Publishing =======
    fun init(otw: NFT, ctx: &mut TxContext) {
        let keys = vector[
            utf8(b"name"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"{img_url}"),
            // Description is static for all `BeLaunchNFT` objects.
            utf8(b"{description} - Minted by BeLaunch"),
            // Project URL is usually static
            utf8(b"https://belaunch.io/"),
            // Creator field can be any
            utf8(b"Unknown Sui Fan")
        ];

        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);

        // Get a new `Display` object for the `BeLaunchNFT` type.
        let display = display::new_with_fields<BeLaunchNFT>(
            &publisher, keys, values, ctx
        );

        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);

        let owner = tx_context::sender(ctx);
        transfer::public_transfer(publisher, owner);
        transfer::public_transfer(display, owner);
    }

    /// Create a new BeLaunch_nft
    public entry fun mint(
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let nft = BeLaunchNFT {
            id: object::new(ctx),
            name: utf8(name),
            description: utf8(description),
            image_url: url::new_unsafe_from_bytes(url)
        };

        let sender = tx_context::sender(ctx);
        event::emit(MintNFTEvent {
            object_id: object::uid_to_inner(&nft.id),
            creator: sender,
            name: nft.name,
        });
        transfer::transfer(nft, sender);
    }

    /// Update the `description` of `nft` to `new_description`
    public entry fun update_description(
        nft: &mut BeLaunchNFT,
        new_description: vector<u8>,
    ) {
        nft.description = utf8(new_description)
    }

    /// Permanently delete `nft`
    public entry fun burn(nft: BeLaunchNFT) {
        let BeLaunchNFT { id, name: _, description: _, image_url: _ } = nft;
        object::delete(id)
    }

    /// Get the NFT's `name`
    public fun name(nft: &BeLaunchNFT): &String {
        &nft.name
    }

    /// Get the NFT's `description`
    public fun description(nft: &BeLaunchNFT): &String {
        &nft.description
    }

    /// Get the NFT's `url`
    public fun url(nft: &BeLaunchNFT): &Url {
        &nft.image_url
    }
}